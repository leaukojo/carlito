// Weight transfer: set the mass, how hard the vehicle brakes, accelerates or turns, the height of
// its centre of mass and the distance between its wheels, and see how much load moves between them:
// m x a x h / L. Plain JS and SVG (the live formula in MathML), no libraries.
// Figures: none from the simulator. The defaults are the page's worked example (1,000 kg braking at
// 8 m/s2, centre of mass 0.5 m high, wheelbase 2.5 m, track 1.6 m).
// Drawing only: the centre of mass sits midway between the wheels (an even split at rest), the
// body's height (h plus the larger of h and 0.9 m) and the wheels' size; the vehicle is rigid and
// does not lean. Every force arrow is to one scale: the whole weight is LOAD_PX long, tip to tail.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var G = 9.81;
  var S = 45;                         // px per metre
  var CX = 220, GROUND = 196;
  var WHEEL_R = 0.3;                  // m
  var LOAD_PX = 60;                   // the whole weight, as an arrow
  var HEAD = 9, HEAD_W = 5;           // arrowheads: length, half-width
  var PUSH_Y = GROUND + 9;            // the road's push, just under the road surface
  var LOAD_TIP = GROUND + 22;         // the load arrows' tips
  var DIM_Y = LOAD_TIP + LOAD_PX + 8, KEY_Y = DIM_Y + 21;
  var MODES = {
    brake: { a: 'Braking', l: 'Wheelbase', gain: 'front', lose: 'rear', side: true },
    drive: { a: 'Acceleration', l: 'Wheelbase', gain: 'rear', lose: 'front', side: true },
    corner: { a: 'Cornering', l: 'Track', gain: 'outside', lose: 'inside', side: false }
  };

  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function text(parent, x, y, extra) {
    return el('text', Object.assign({ x: x, y: y, 'font-size': 12, fill: 'var(--fig-muted)' }, extra || {}), parent);
  }
  // An arrow whose tip lands exactly on its end point: a shaft and a filled head of fixed size,
  // the head shrinking only when the whole arrow is shorter than it. Under 4 px it is not drawn,
  // since a speck of a head reads as a mark, not a force.
  function makeArrow(parent, width, dashed) {
    var g = el('g', {}, parent);
    var shaft = el('line', { 'stroke-width': width, 'stroke-dasharray': dashed ? '6 4' : 'none' }, g);
    var head = el('path', {}, g);
    return {
      colour: function (c) { shaft.setAttribute('stroke', c); head.setAttribute('fill', c); },
      set: function (x1, y1, x2, y2) {
        var dx = x2 - x1, dy = y2 - y1, len = Math.sqrt(dx * dx + dy * dy);
        g.style.display = len < 4 ? 'none' : '';
        if (len < 4) return;
        var ux = dx / len, uy = dy / len, hl = Math.min(HEAD, len), hw = HEAD_W * hl / HEAD;
        var bx = x2 - ux * hl, by = y2 - uy * hl;
        shaft.setAttribute('x1', x1); shaft.setAttribute('y1', y1);
        shaft.setAttribute('x2', bx); shaft.setAttribute('y2', by);
        head.setAttribute('d', 'M' + x2 + ',' + y2 + ' L' + (bx - uy * hw) + ',' + (by + ux * hw) +
          ' L' + (bx + uy * hw) + ',' + (by - ux * hw) + ' Z');
      }
    };
  }
  function fmt(n, digits) {
    return n.toLocaleString('en-GB', { minimumFractionDigits: digits || 0, maximumFractionDigits: digits || 0 });
  }
  function mn(n, digits) { return '<mn>' + fmt(n, digits) + '</mn>'; }
  function frac(top, bottom) { return '<mfrac><mrow>' + top + '</mrow><mrow>' + bottom + '</mrow></mfrac>'; }
  var TIMES = '<mo>×</mo>';

  function make(root) {
    root.innerHTML = '';
    var uid = 'wt' + Math.random().toString(36).slice(2, 8);
    var svg = el('svg', { viewBox: '0 0 440 ' + (KEY_Y + 6), role: 'img' }, root);

    el('line', { x1: 10, y1: GROUND, x2: 430, y2: GROUND, stroke: 'var(--fig-grid)', 'stroke-width': 4 }, svg);
    var body = el('rect', { rx: 8, fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 2 }, svg);
    var facing = text(svg, 0, 0);
    var wheels = [0, 1].map(function () {
      return el('rect', { fill: 'var(--fig-ink)' }, svg);
    });
    // h, from the road up to the centre of mass, and L, between the wheels' contact points.
    var hLine = el('line', { stroke: 'var(--fig-muted)', 'stroke-width': 1 }, svg);
    var hLabel = text(svg, 0, 0, { 'font-style': 'italic', 'text-anchor': 'end' });
    hLabel.textContent = 'h';
    var lLine = el('line', { y1: DIM_Y, y2: DIM_Y, stroke: 'var(--fig-muted)', 'stroke-width': 1 }, svg);
    var lTicks = el('path', { stroke: 'var(--fig-muted)', 'stroke-width': 1 }, svg);
    var lLabel = text(svg, CX, DIM_Y - 4, { 'text-anchor': 'middle', 'font-style': 'italic' });
    lLabel.textContent = 'L';
    // The road's push on the tyres (orange) and the body carrying on (blue): equal, h apart.
    var push = makeArrow(svg, 3, false);
    push.colour('var(--fig-orange)');
    var carry = makeArrow(svg, 3, true);
    carry.colour('var(--fig-blue)');
    var com = el('g', {}, svg);
    el('circle', { r: 6, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, com);
    el('path', { d: 'M0,-6 A6,6 0 0 1 6,0 L0,0 Z M0,6 A6,6 0 0 1 -6,0 L0,0 Z', fill: 'var(--fig-ink)' }, com);
    // The road pushing up on each end, from below into the tyres; the dashed tick is the load at rest.
    var loads = [0, 1].map(function () {
      return {
        arrow: makeArrow(svg, 4, false),
        rest: el('line', { stroke: 'var(--fig-muted)', 'stroke-width': 1.5, 'stroke-dasharray': '3 2' }, svg),
        label: text(svg, 0, 0, { 'font-weight': 600 })
      };
    });
    // The key, along the bottom.
    var keyX = 12;
    [['var(--fig-orange)', 'none', 'road’s push on the tyres'], ['var(--fig-blue)', '6 4', 'the body carrying on'],
      ['var(--fig-muted)', '3 2', 'load at rest']].forEach(function (k) {
      el('line', { x1: keyX, y1: KEY_Y - 4, x2: keyX + 18, y2: KEY_Y - 4, stroke: k[0], 'stroke-width': 3,
        'stroke-dasharray': k[1] }, svg);
      var t = text(svg, keyX + 23, KEY_Y);
      t.textContent = k[2];
      keyX += 23 + (t.getComputedTextLength() || 6.5 * k[2].length) + 16;
    });

    var controls = document.createElement('div');
    controls.className = 'w-controls';
    function row(id, label, min, max, step, value) {
      return '<label for="' + uid + '-' + id + '">' + label + '</label>' +
        '<input id="' + uid + '-' + id + '" type="range" min="' + min + '" max="' + max + '" step="' + step +
        '" value="' + value + '"><output for="' + uid + '-' + id + '"></output>';
    }
    controls.innerHTML =
      '<label for="' + uid + '-mode">The vehicle is</label>' +
      '<select id="' + uid + '-mode"><option value="brake">braking</option>' +
      '<option value="drive">accelerating</option><option value="corner">cornering</option></select><span></span>' +
      row('m', 'Mass (<i>m</i>)', 500, 5000, 50, 1000) +
      row('a', '', 0, 12, 0.1, 8) +
      row('h', 'Height of the centre of mass (<i>h</i>)', 0.3, 2, 0.05, 0.5) +
      row('l', '', 1.5, 6, 0.05, 2.5);
    root.appendChild(controls);
    var mode = controls.querySelector('select');
    function input(id) { return controls.querySelector('#' + uid + '-' + id); }
    function label(id) { return controls.querySelector('label[for="' + uid + '-' + id + '"]'); }
    function output(id) { return controls.querySelector('output[for="' + uid + '-' + id + '"]'); }
    var inM = input('m'), inA = input('a'), inH = input('h'), inL = input('l');
    // The wheelbase and the track keep their own values while the mode changes.
    var dist = { side: 2.5, rear: 1.6 };
    var lastSide = true;

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function update() {
      var M = MODES[mode.value];
      if (M.side !== lastSide) {
        dist[lastSide ? 'side' : 'rear'] = parseFloat(inL.value);
        lastSide = M.side;
        inL.min = M.side ? 1.5 : 1;
        inL.max = M.side ? 6 : 2.6;
        inL.value = dist[M.side ? 'side' : 'rear'];
      }
      var m = parseFloat(inM.value), a = parseFloat(inA.value);
      var h = parseFloat(inH.value), L = parseFloat(inL.value);
      label('a').innerHTML = M.a + ' (<i>a</i>)';
      label('l').innerHTML = M.l + ' (<i>L</i>)';
      output('m').textContent = fmt(m) + ' kg';
      output('a').textContent = fmt(a, 1) + ' m/s² (' + fmt(a / G, 2) + ' g)';
      output('h').textContent = fmt(h, 2) + ' m';
      output('l').textContent = fmt(L, 2) + ' m';

      var W = m * G, dF = m * a * h / L;
      var lift = dF > W / 2;
      var moved = Math.min(dF, W / 2);
      var aLift = G * (L / 2) / h;

      // Side view: the car faces right. Rear view: the car turns left, so the outside is on the
      // right. forward: +1 when the end that gains load is on the right.
      var forward = mode.value === 'drive' ? -1 : 1;
      var top = GROUND - (h + Math.max(h, 0.9)) * S;
      var floor = GROUND - Math.min(0.3, h - 0.12) * S;
      var gainX = CX + forward * L / 2 * S, loseX = CX - forward * L / 2 * S;
      var halfBody = M.side ? (L / 2 + 0.8) * S : (L / 2 + 0.2) * S;
      body.setAttribute('x', CX - halfBody); body.setAttribute('width', 2 * halfBody);
      body.setAttribute('y', top); body.setAttribute('height', floor - top);
      facing.textContent = M.side ? 'front →' : '← turning left';
      facing.setAttribute('x', M.side ? CX + halfBody : CX - halfBody);
      facing.setAttribute('y', top - 6);
      facing.setAttribute('text-anchor', M.side ? 'end' : 'start');
      var wR = WHEEL_R * S, wW = M.side ? 2 * wR : 0.26 * S;
      [gainX, loseX].forEach(function (x, i) {
        var up = i === 1 && lift ? 6 : 0;
        wheels[i].setAttribute('x', x - wW / 2); wheels[i].setAttribute('width', wW);
        wheels[i].setAttribute('y', GROUND - 2 * wR - up); wheels[i].setAttribute('height', 2 * wR);
        wheels[i].setAttribute('rx', M.side ? wR : 3);
      });
      var comY = GROUND - h * S;
      com.setAttribute('transform', 'translate(' + CX + ',' + comY + ')');
      // h stands just left of the body; its label sits beside it, or above it when it is short.
      var hx = CX - halfBody - 12;
      hLine.setAttribute('x1', hx); hLine.setAttribute('x2', hx);
      hLine.setAttribute('y1', GROUND); hLine.setAttribute('y2', comY);
      var hRoom = GROUND - comY > 20;
      hLabel.setAttribute('x', hRoom ? hx - 4 : hx + 4);
      hLabel.setAttribute('y', hRoom ? (GROUND + comY) / 2 + 4 : comY - 4);
      var lx1 = CX - L / 2 * S, lx2 = CX + L / 2 * S;
      lLine.setAttribute('x1', lx1); lLine.setAttribute('x2', lx2);
      lTicks.setAttribute('d', 'M' + lx1 + ',' + (DIM_Y - 4) + 'V' + (DIM_Y + 4) +
        'M' + lx2 + ',' + (DIM_Y - 4) + 'V' + (DIM_Y + 4));

      // The two equal, opposite forces: the road's push at road level, the body's carrying on at
      // the centre of mass, both m x a long on the load scale.
      var f = LOAD_PX * a / G;
      var sx = M.side ? forward : 1; // which way the body carries on
      push.set(CX, PUSH_Y, CX - sx * f, PUSH_Y);
      carry.set(CX + sx * 6, comY, CX + sx * (6 + f), comY);

      [[gainX, W / 2 + moved, '+', 'green'], [loseX, W / 2 - moved, '−', 'red']].forEach(function (d, i) {
        var o = loads[i], len = LOAD_PX * d[1] / W, x = d[0];
        var colour = 'var(--fig-' + d[3] + ')';
        o.arrow.colour(colour);
        o.arrow.set(x, LOAD_TIP + len, x, LOAD_TIP);
        o.rest.setAttribute('x1', x - 9); o.rest.setAttribute('x2', x + 9);
        o.rest.setAttribute('y1', LOAD_TIP + LOAD_PX / 2); o.rest.setAttribute('y2', LOAD_TIP + LOAD_PX / 2);
        var out = x > CX ? 1 : -1;
        o.label.setAttribute('x', x + out * 12);
        o.label.setAttribute('y', LOAD_TIP + LOAD_PX / 4 + 4);
        o.label.setAttribute('text-anchor', out > 0 ? 'start' : 'end');
        o.label.setAttribute('fill', colour);
        o.label.textContent = i === 1 && lift ? 'lifts' : d[2] + fmt(Math.round(moved / 10) * 10) + ' N';
      });

      var share = Math.round(dF / W * 100);
      var said = lift
        ? '<strong>More than the ' + M.lose + ' wheels carry:</strong> they lift off the road, and the ' +
          'vehicle tips over its ' + M.gain + ' wheels.'
        : 'About the weight of <strong>' + fmt(Math.round(dF / G)) + ' kg</strong> moves from the ' + M.lose +
          ' wheels to the ' + M.gain + ' ones: <strong>' + share + ' %</strong> of the vehicle’s weight (' +
          fmt(Math.round(W / 100) * 100) + ' N).';
      said += ' The ' + M.lose + ' wheels lift at ' + fmt(aLift, 1) + ' m/s² (' + fmt(aLift / G, 2) + ' g).';
      readout.innerHTML =
        '<math display="block"><mi>ΔF</mi><mo>=</mo>' +
        frac('<mi>m</mi>' + TIMES + '<mi>a</mi>' + TIMES + '<mi>h</mi>', '<mi>L</mi>') + '<mo>=</mo>' +
        frac(mn(m) + TIMES + mn(a, 1) + TIMES + mn(h, 2), mn(L, 2)) + '<mo>=</mo>' +
        mn(Math.round(dF)) + '<mtext>&nbsp;N</mtext></math>' + said;
      svg.setAttribute('aria-label', (M.side ? 'A vehicle from the side, ' : 'A vehicle from behind, ') +
        mode.selectedOptions[0].textContent + ': ' + said.replace(/<[^>]+>/g, ''));
    }
    mode.addEventListener('change', update);
    [inM, inA, inH, inL].forEach(function (i) { i.addEventListener('input', update); });
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['weight-transfer'] = make;
})();
