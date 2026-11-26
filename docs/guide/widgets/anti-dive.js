// Anti-dive and anti-squat: tilt the rigid link that holds a wheel and see how the extra load on
// that axle splits between the spring and the link, and so how much the body dives (braking) or
// squats (accelerating). Plain JS and SVG, no libraries.
// Figures, all read from the simulator:
//   GroundDriveSpec.anti_dive_slope / anti_squat_slope: the link's side-view slope; a tyre force F
//                  puts F x slope through the links; slope = h / wheelbase holds off 100 %
//   sedan_spec.tres anti_dive_slope 0.121 (40 %), anti_squat_slope 0.152 (50 %), so h / wheelbase
//                  is 0.3025 on the sedan
// Drawing only, not the simulator: the body's pitch (4 degrees with a flat link), the link drawn
// 1.5 times steeper than it is, the arrows' sizes and the sizes of the parts.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var FULL = 0.3025;                  // slope that holds off 100 %, the sedan's h / wheelbase
  var SEDAN = { brake: 0.121, drive: 0.152 };
  var MAX_DEG = Math.atan(FULL) * 180 / Math.PI;
  var PITCH_DEG = 4;                  // drawing: pitch with a flat link
  var DRAW_GAIN = 1.5;                // drawing: the link looks steeper than it is
  var LOAD_PX = 44;                   // drawing: the axle's extra load, as an arrow
  // Side view, car facing right; drawn 14 below its own coordinates to clear the two text lines.
  var SHIFT = -14;
  var GROUND = 206, WHEEL_R = 28, HUB_Y = GROUND - WHEEL_R;
  var REAR_X = 110, FRONT_X = 310, PIVOT = [210, 122];
  var LINK_LEN = 60, FLOOR = 150;

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
  function marker(defs, id, colour) {
    var m = el('marker', { id: id, viewBox: '0 0 10 10', refX: 8, refY: 5, markerWidth: 6, markerHeight: 6,
      orient: 'auto-start-reverse' }, defs);
    el('path', { d: 'M0,0 L10,5 L0,10 z', fill: colour }, m);
  }
  function rot(pt, deg) {
    var a = deg * Math.PI / 180, dx = pt[0] - PIVOT[0], dy = pt[1] - PIVOT[1];
    return [PIVOT[0] + dx * Math.cos(a) - dy * Math.sin(a), PIVOT[1] + dx * Math.sin(a) + dy * Math.cos(a)];
  }
  function setLine(l, a, b) {
    l.setAttribute('x1', a[0]); l.setAttribute('y1', a[1]);
    l.setAttribute('x2', b[0]); l.setAttribute('y2', b[1]);
  }
  // A coil spring between two points on a vertical line.
  function coil(x, yBottom, yTop) {
    var n = 6, w = 7, d = 'M' + x + ',' + yBottom + ' L' + x + ',' + (yBottom - 3);
    var span = (yBottom - 3) - (yTop + 3);
    for (var i = 0; i < n; i++) {
      d += ' L' + (x + (i % 2 ? -w : w)) + ',' + (yBottom - 3 - span * (i + 0.5) / n);
    }
    return d + ' L' + x + ',' + (yTop + 3) + ' L' + x + ',' + yTop;
  }
  function vArrow(path, x, y, len) {
    if (len < 3) { path.style.display = 'none'; return; }
    path.style.display = '';
    path.setAttribute('d', 'M' + x + ',' + y + ' L' + x + ',' + (y - len));
  }
  // The car's side, facing right, at rest.
  var BODY = 'M58,150 L58,112 Q60,100 80,98 L140,96 L170,66 L262,66 L300,96 L352,102 Q372,106 372,124 ' +
    'L372,150 Z';

  function make(root) {
    root.innerHTML = '';
    root.classList.add('widget-anti-dive');
    var uid = 'ad' + Math.random().toString(36).slice(2, 8);
    var svg = el('svg', { viewBox: '0 0 420 ' + (GROUND + SHIFT + 8), role: 'img' }, root);
    var defs = el('defs', {}, svg);
    marker(defs, uid + '-orange', 'var(--fig-orange)');
    marker(defs, uid + '-blue', 'var(--fig-blue)');

    var state = text(svg, 20, 20, '', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    var split = text(svg, 20, 38, '');

    var side = el('g', { transform: 'translate(0,' + SHIFT + ')' }, svg);
    text(side, 400, 76, 'front →', { 'text-anchor': 'end' });
    el('line', { x1: 20, y1: GROUND, x2: 400, y2: GROUND, stroke: 'var(--fig-grid)', 'stroke-width': 6 }, side);
    var ghost = el('path', { d: BODY, fill: 'none', stroke: 'var(--fig-muted)', 'stroke-width': 1.5,
      'stroke-dasharray': '5 4' }, side);
    var body = el('path', { d: BODY, fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 2 }, side);
    [REAR_X, FRONT_X].forEach(function (x) {
      el('circle', { cx: x, cy: HUB_Y, r: WHEEL_R, fill: 'var(--fig-ink)' }, side);
    });
    var lug = el('path', { fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 2,
      'stroke-linejoin': 'round' }, side);
    var spring = el('path', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 2.5,
      'stroke-linejoin': 'round' }, side);
    var link = el('line', { stroke: 'var(--fig-orange)', 'stroke-width': 6, 'stroke-linecap': 'round' }, side);
    var hub = el('circle', { r: 5, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, side);
    var joint = el('circle', { r: 5, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, side);
    var springPush = el('path', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3,
      'marker-end': 'url(#' + uid + '-blue)' }, side);
    var linkPush = el('path', { fill: 'none', stroke: 'var(--fig-orange)', 'stroke-width': 3,
      'marker-end': 'url(#' + uid + '-orange)' }, side);

    // controls
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-m">The car is</label>' +
      '<select id="' + uid + '-m"><option value="brake">braking</option>' +
      '<option value="drive">accelerating</option></select><span></span>' +
      '<label for="' + uid + '-a">Link angle</label>' +
      '<input id="' + uid + '-a" type="range" min="0" max="' + MAX_DEG.toFixed(1) + '" step="0.1">' +
      '<output for="' + uid + '-a" aria-live="polite"></output>';
    root.appendChild(controls);
    var mode = controls.querySelector('select');
    var angle = controls.querySelector('input');
    var out = controls.querySelector('output');
    function sedanAngle() { return (Math.atan(SEDAN[mode.value]) * 180 / Math.PI).toFixed(1); }
    angle.value = sedanAngle();

    function update() {
      var brake = mode.value === 'brake';
      var deg = parseFloat(angle.value);
      var slope = Math.tan(deg * Math.PI / 180);
      var share = Math.min(1, slope / FULL);
      // Braking dips the nose (clockwise on screen), accelerating drops the tail. Dashed: the body
      // with a flat link.
      var sign = brake ? 1 : -1;
      var pitch = sign * PITCH_DEG * (1 - share);
      ghost.setAttribute('transform', 'rotate(' + sign * PITCH_DEG + ' ' + PIVOT[0] + ' ' + PIVOT[1] + ')');
      body.setAttribute('transform', 'rotate(' + pitch + ' ' + PIVOT[0] + ' ' + PIVOT[1] + ')');

      // The link runs from the hub towards the car's middle, rising at the drawn angle, to a lug on
      // the body. The spring stands on the hub, straight up to the body's floor.
      var hx = brake ? FRONT_X : REAR_X, dir = brake ? -1 : 1;
      var drawn = Math.atan(slope * DRAW_GAIN);
      var rest = [hx + dir * LINK_LEN * Math.cos(drawn), HUB_Y - LINK_LEN * Math.sin(drawn)];
      // The joint keeps the chosen angle; the lug stretches the small way to the pitched body.
      var j = rest;
      var l1 = rot([rest[0] - 9, FLOOR], pitch), l2 = rot([rest[0] + 9, FLOOR], pitch);
      lug.setAttribute('d', 'M' + l1 + ' L' + j + ' L' + l2);
      setLine(link, [hx, HUB_Y], j);
      hub.setAttribute('cx', hx); hub.setAttribute('cy', HUB_Y);
      joint.setAttribute('cx', j[0]); joint.setAttribute('cy', j[1]);
      var sTop = rot([hx, FLOOR], pitch);
      spring.setAttribute('d', coil(hx, HUB_Y, sTop[1]));

      // The axle's extra load is the same at any link angle; the link takes `share` of it, the
      // spring the rest, and only the spring's part compresses it.
      vArrow(springPush, sTop[0], sTop[1] - 4, LOAD_PX * (1 - share));
      var lugTop = rot([rest[0], FLOOR], pitch);
      vArrow(linkPush, lugTop[0], lugTop[1] - 4, LOAD_PX * share);

      out.textContent = deg.toFixed(1) + '°';
      var pct = Math.round(share * 100);
      var what = brake ? 'dive' : 'squat';
      state.textContent = pct === 0 ? 'flat link: the full ' + what
        : pct >= 100 ? 'the link holds off all the ' + what
        : 'the link holds off ' + pct + ' % of the ' + what;
      // The key to the colours: the springs blue, the links orange, as drawn.
      split.textContent = 'extra load on the ' + (brake ? 'front' : 'rear') + ' axle: ';
      el('tspan', { fill: 'var(--fig-blue)', 'font-weight': 600 }, split).textContent = 'springs ' + (100 - pct) + ' %';
      el('tspan', {}, split).textContent = ', ';
      el('tspan', { fill: 'var(--fig-orange)', 'font-weight': 600 }, split).textContent = 'links ' + pct + ' %';
      svg.setAttribute('aria-label', 'A car seen from the side, ' + (brake ? 'braking' : 'accelerating') +
        ': ' + state.textContent);
    }
    mode.addEventListener('change', function () { angle.value = sedanAngle(); update(); });
    angle.addEventListener('input', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['anti-dive'] = make;
})();
