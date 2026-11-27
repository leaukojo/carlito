// Anti-roll bar: move each wheel of one axle up or down and watch the bar rotate or twist, and push
// back. Plain JS and SVG, no libraries.
// Figures: VehicleMath.anti_roll_force is rate x (left compression - right compression), equal and
// opposite, so the red arrows grow with the difference between the wheels and vanish without one.
// Drawing only, not the simulator: the arm and link lengths, and the marks along the bar, which
// turn twice as far as the bar would so that a twist shows.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var MAX_CM = 8;          // slider range, each way
  var PX_CM = 3;           // wheel travel on screen
  var CX = 222, BASE = 64; // projection origin
  var ARM = 80;            // arm length (runs towards the viewer)
  var BAR_X = 100;         // the bar's ends, either side of the centre
  var MOUNT_X = 70;        // the two mounts on the body
  var WHEEL_X = 160;       // wheel centres
  var LINK = 40;           // drop link, arm end down to the wheel's hub
  var TYRE_W = 13, TYRE_H = 40;
  var BAR_W = 12;          // bar thickness on screen
  var MARK_X = [-55, -30, 30, 55];
  var MARK_HALF = 5.5, MARK_GAIN = 2;
  var AXIS_X = 122;        // the dashed turning axis reaches past the bar's ends
  var RING_RX = 9, RING_RY = 18; // the fixed turn arrow round the axis, at the centre

  // Oblique view from behind and above: x across the car (left to right), y up, z towards the viewer.
  function p(x, y, z) { return [CX + x - 0.3 * z, BASE - y + 0.5 * z]; }
  function pt(a) { return a[0].toFixed(1) + ',' + a[1].toFixed(1); }
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
  function line(parent, a, b, attrs) {
    return el('line', Object.assign({ x1: a[0], y1: a[1], x2: b[0], y2: b[1] }, attrs), parent);
  }
  function setLine(l, a, b) {
    l.setAttribute('x1', a[0]); l.setAttribute('y1', a[1]);
    l.setAttribute('x2', b[0]); l.setAttribute('y2', b[1]);
  }

  function make(root) {
    root.innerHTML = '';
    root.classList.add('widget-anti-roll-bar');
    var uid = 'ar' + Math.random().toString(36).slice(2, 8);
    var svg = el('svg', { viewBox: '0 0 420 234', role: 'img' }, root);
    var defs = el('defs', {}, svg);
    var mk = el('marker', { id: uid + '-red', viewBox: '0 0 10 10', refX: 8, refY: 5, markerWidth: 6,
      markerHeight: 6, orient: 'auto-start-reverse' }, defs);
    el('path', { d: 'M0,0 L10,5 L0,10 z', fill: 'var(--fig-red)' }, mk);
    var mkInk = el('marker', { id: uid + '-ink', viewBox: '0 0 10 10', refX: 8, refY: 5, markerWidth: 5,
      markerHeight: 5, orient: 'auto-start-reverse' }, defs);
    el('path', { d: 'M0,0 L10,5 L0,10 z', fill: 'var(--fig-ink)' }, mkInk);

    var ink = { stroke: 'var(--fig-ink)', 'stroke-width': 2 };
    var rest = { stroke: 'var(--fig-muted)', 'stroke-width': 1.5, 'stroke-dasharray': '4 3' };

    // body and the two mounts the bar turns in
    line(svg, p(-125, 30, 0), p(125, 30, 0), ink);
    text(svg, p(125, 30, 0)[0] + 8, p(125, 30, 0)[1] + 4, 'body');
    [-MOUNT_X, MOUNT_X].forEach(function (x) { line(svg, p(x, 30, 0), p(x, 8, 0), ink); });
    text(svg, p(-MOUNT_X, 20, 0)[0] + 8, p(-MOUNT_X, 20, 0)[1] + 4, 'mount');

    // arms at rest, dashed
    [-1, 1].forEach(function (s) { line(svg, p(s * BAR_X, 0, 0), p(s * BAR_X, 0, ARM), rest); });

    // per side: tyre, hub stub, drop link, joint, push arrow
    function side(s) {
      var v = {};
      v.tyre = el('rect', { width: 2 * TYRE_W, height: 2 * TYRE_H, rx: 7, fill: 'var(--fig-ink)' }, svg);
      v.stub = line(svg, [0, 0], [0, 0], { stroke: 'var(--fig-ink)', 'stroke-width': 4, 'stroke-linecap': 'round' });
      v.link = line(svg, [0, 0], [0, 0], { stroke: 'var(--fig-ink)', 'stroke-width': 2.5 });
      v.push = el('path', { fill: 'none', stroke: 'var(--fig-red)', 'stroke-width': 2.5,
        'marker-end': 'url(#' + uid + '-red)' }, svg);
      v.s = s;
      return v;
    }
    var L = side(-1), R = side(1);
    var bar = el('path', { fill: 'none', stroke: 'var(--fig-orange)', 'stroke-width': BAR_W,
      'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, svg);
    var marks = MARK_X.map(function () {
      return line(svg, [0, 0], [0, 0], { stroke: 'var(--surface)', 'stroke-width': 2, 'stroke-linecap': 'round' });
    });
    // The axis the bar turns about (dashed, past both ends) and a fixed turn arrow round it. The
    // ring is an upright ellipse; its gap and head sit at the bottom.
    line(svg, p(-AXIS_X, 0, 0), p(AXIS_X, 0, 0), { stroke: 'var(--fig-ink)', 'stroke-width': 1.2,
      'stroke-dasharray': '5 3' });
    var c0 = p(0, 0, 0), ring = '';
    for (var k = 0; k <= 32; k++) {
      var s = 0.55 + (2 * Math.PI - 1.1) * k / 32;
      ring += (k ? ' L' : 'M') + pt([c0[0] - RING_RX * Math.sin(s), c0[1] + RING_RY * Math.cos(s)]);
    }
    el('path', { d: ring, fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.8,
      'marker-end': 'url(#' + uid + '-ink)' }, svg);
    [-MOUNT_X, MOUNT_X].forEach(function (x) {
      var c = p(x, 0, 0);
      el('rect', { x: c[0] - 7, y: c[1] - 9, width: 14, height: 18, rx: 2, fill: 'var(--fig-muted)',
        stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    });
    [L, R].forEach(function (v) {
      v.joint = el('circle', { r: 4, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
      v.hub = el('circle', { r: 4, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    });
    var state = text(svg, CX - 12, 180, '', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, p(-WHEEL_X, 0, ARM)[0], 228, 'left wheel', { 'text-anchor': 'middle' });
    text(svg, p(WHEEL_X, 0, ARM)[0], 228, 'right wheel', { 'text-anchor': 'middle' });

    // controls
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-l">Left wheel</label>' +
      '<input id="' + uid + '-l" type="range" min="-' + MAX_CM + '" max="' + MAX_CM + '" step="0.5" value="4">' +
      '<output for="' + uid + '-l"></output>' +
      '<label for="' + uid + '-r">Right wheel</label>' +
      '<input id="' + uid + '-r" type="range" min="-' + MAX_CM + '" max="' + MAX_CM + '" step="0.5" value="-4">' +
      '<output for="' + uid + '-r"></output>';
    root.appendChild(controls);
    var inL = controls.querySelector('#' + uid + '-l'), inR = controls.querySelector('#' + uid + '-r');
    var outs = controls.querySelectorAll('output');
    outs[0].setAttribute('aria-live', 'polite');
    outs[1].setAttribute('aria-live', 'polite');

    function fmt(cm) {
      if (cm === 0) return 'at rest';
      return (cm > 0 ? '+' : '−') + Math.abs(cm).toFixed(1) + ' cm ' + (cm > 0 ? 'up' : 'down');
    }

    // One side: wheel travel h (px), returns the arm's angle and its end on screen.
    function place(v, h) {
      var ang = Math.asin(h / ARM);
      var end3 = [v.s * BAR_X, h, ARM * Math.cos(ang)];
      var end = p(end3[0], end3[1], end3[2]);
      var hub = p(v.s * BAR_X, h - LINK, ARM);
      var wc = p(v.s * WHEEL_X, h - LINK, ARM);
      v.tyre.setAttribute('x', wc[0] - TYRE_W); v.tyre.setAttribute('y', wc[1] - TYRE_H);
      setLine(v.stub, p(v.s * (WHEEL_X - TYRE_W), h - LINK, ARM), hub);
      setLine(v.link, hub, end);
      v.joint.setAttribute('cx', end[0]); v.joint.setAttribute('cy', end[1]);
      v.hub.setAttribute('cx', hub[0]); v.hub.setAttribute('cy', hub[1]);
      return { ang: ang, end: end, hub: hub };
    }

    function update() {
      var l = parseFloat(inL.value), r = parseFloat(inR.value);
      var a = place(L, l * PX_CM), b = place(R, r * PX_CM);
      bar.setAttribute('d', 'M' + pt(a.end) + ' L' + pt(p(-BAR_X, 0, 0)) + ' L' + pt(p(BAR_X, 0, 0)) +
        ' L' + pt(b.end));
      // Each mark turns with the bar where it sits: the same everywhere is a turn, a fan is a twist.
      MARK_X.forEach(function (x, i) {
        var phi = MARK_GAIN * (a.ang + (b.ang - a.ang) * (x + BAR_X) / (2 * BAR_X));
        var dy = MARK_HALF * Math.sin(phi), dz = MARK_HALF * Math.cos(phi);
        setLine(marks[i], p(x, -dy, -dz), p(x, dy, dz));
      });

      // The bar pushes the higher wheel down and the lower one up, harder the bigger the difference.
      var len = Math.min(36, 2.2 * Math.abs(l - r));
      var down = l > r ? 1 : -1;                      // screen +y = down, for the left wheel
      // Drawn beside each link, on the inner side, clear of the arm and the tyre.
      [[L, a, down], [R, b, -down]].forEach(function (q) {
        if (len < 3) { q[0].push.style.display = 'none'; return; }
        q[0].push.style.display = '';
        var x = q[1].hub[0] - q[0].s * 18, y = (q[1].hub[1] + q[1].end[1]) / 2;
        q[0].push.setAttribute('d', 'M' + x + ',' + (y - q[2] * len / 2) + ' L' + x + ',' + (y + q[2] * len / 2));
      });

      outs[0].textContent = fmt(l);
      outs[1].textContent = fmt(r);
      state.textContent = l === r
        ? (l === 0 ? 'at rest' : 'no twist: the whole bar rotates')
        : 'twisted: it pushes back';
      svg.setAttribute('aria-label', 'An anti-roll bar across one axle, seen from behind: ' + state.textContent);
    }
    inL.addEventListener('input', update);
    inR.addEventListener('input', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['anti-roll-bar'] = make;
})();
