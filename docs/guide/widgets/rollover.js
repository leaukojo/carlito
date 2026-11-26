// Wheel lift and rollover: a vehicle from behind, cornering. The weight (down) and the body's
// carrying on (outwards) add up to one push through the centre of mass (drawn beside the vehicle); while its line reaches the
// road between the wheels the vehicle stands, and once it lands outside the outside wheel the
// vehicle tips. The tyres can only give mu x g sideways, so a low, wide vehicle slides first.
// Plain JS and SVG, no libraries.
// Figures: none from the simulator. The two examples are the page's worked ones: a car (track
// 1.6 m, centre of mass 0.5 m high) and a loaded truck (track 2 m, centre of mass 2 m high).
// Drawing only: the vehicle is rigid (it does not lean on its springs, so its wheels lift and it
// tips at the same moment), the tipped pose is a fixed 8 degrees, the body's height and the wheels'
// size are only a drawing.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var G = 9.81;
  var S = 40;                         // px per metre
  var CX = 230, GROUND = 196;
  var FORCE_PX = 50;                  // the weight, as an arrow in the force diagram
  var IX = 70, IY = 40;               // the force diagram's corner
  var LOAD_PX = 44;                   // the whole weight, as a load arrow under the wheels
  var HEAD = 9, HEAD_W = 5;
  var LOAD_TIP = GROUND + 18;
  var BAR_Y = LOAD_TIP + LOAD_PX + 26, BAR_X0 = 40, BAR_X1 = 420, BAR_MAX = 20; // m/s2
  var TIP_DEG = 8;
  var VEHICLES = {
    car: { name: 'Car', icon: 'car', track: 1.6, h: 0.5, wheel: 0.3 },
    truck: { name: 'Loaded truck', icon: 'truck', track: 2, h: 2, wheel: 0.5 }
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
  // An arrow whose tip lands exactly on its end point (see widgets/weight-transfer.js).
  function makeArrow(parent, width, colour, dashed) {
    var g = el('g', {}, parent);
    var shaft = el('line', { 'stroke-width': width, stroke: colour, 'stroke-dasharray': dashed ? '6 4' : 'none' }, g);
    var head = el('path', { fill: colour }, g);
    return function (x1, y1, x2, y2) {
      var dx = x2 - x1, dy = y2 - y1, len = Math.sqrt(dx * dx + dy * dy);
      g.style.display = len < 4 ? 'none' : '';
      if (len < 4) return;
      var ux = dx / len, uy = dy / len, hl = Math.min(HEAD, len), hw = HEAD_W * hl / HEAD;
      var bx = x2 - ux * hl, by = y2 - uy * hl;
      shaft.setAttribute('x1', x1); shaft.setAttribute('y1', y1);
      shaft.setAttribute('x2', bx); shaft.setAttribute('y2', by);
      head.setAttribute('d', 'M' + x2 + ',' + y2 + ' L' + (bx - uy * hw) + ',' + (by + ux * hw) +
        ' L' + (bx + uy * hw) + ',' + (by - ux * hw) + ' Z');
    };
  }
  function fmt(n, digits) {
    return n.toLocaleString('en-GB', { minimumFractionDigits: digits || 0, maximumFractionDigits: digits || 0 });
  }
  function barX(a) { return BAR_X0 + (BAR_X1 - BAR_X0) * Math.min(a, BAR_MAX) / BAR_MAX; }

  function make(root) {
    root.innerHTML = '';
    var uid = 'ro' + Math.random().toString(36).slice(2, 8);
    var current = 'car';
    GuideKit.vehiclePicker(root, Object.keys(VEHICLES).map(function (id) {
      return { id: id, icon: VEHICLES[id].icon, name: VEHICLES[id].name };
    }), current, function (id) {
      current = id;
      inT.value = VEHICLES[id].track;
      inH.value = VEHICLES[id].h;
      update();
    });
    var svg = el('svg', { viewBox: '0 0 440 ' + (BAR_Y + 30), role: 'img' }, root);

    el('line', { x1: 10, y1: GROUND, x2: 430, y2: GROUND, stroke: 'var(--fig-grid)', 'stroke-width': 4 }, svg);
    // The vehicle, turned about its outside contact point when it tips.
    var veh = el('g', {}, svg);
    var body = el('rect', { rx: 8, fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 2 }, veh);
    var wheels = [0, 1].map(function () { return el('rect', { rx: 3, fill: 'var(--fig-ink)' }, veh); });
    var facing = text(svg, 430, 16, { 'text-anchor': 'end' });
    facing.textContent = '← turning left';
    // The line of the combined push, from the centre of mass to the road, and where it lands.
    var reach = el('line', { stroke: 'var(--fig-ink)', 'stroke-width': 2, 'stroke-dasharray': '4 3' }, svg);
    var land = el('circle', { r: 4.5 }, svg);
    // The force diagram: the weight, the carrying on, and the two added up.
    var weight = makeArrow(svg, 3, 'var(--fig-muted)', false);
    var carry = makeArrow(svg, 3, 'var(--fig-blue)', true);
    var both = makeArrow(svg, 3.5, 'var(--fig-ink)', false);
    text(svg, IX - 6, IY + FORCE_PX / 2 + 4, { 'text-anchor': 'end' }).textContent = 'weight';
    text(svg, IX, IY - 9, { fill: 'var(--fig-blue)' }).textContent = 'carrying on';
    var com = el('g', {}, svg);
    el('circle', { r: 6, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, com);
    el('path', { d: 'M0,-6 A6,6 0 0 1 6,0 L0,0 Z M0,6 A6,6 0 0 1 -6,0 L0,0 Z', fill: 'var(--fig-ink)' }, com);
    // The road pushing up on the inside (left) and outside (right) wheels, as shares of the weight.
    var loads = ['red', 'green'].map(function (c) {
      return {
        arrow: makeArrow(svg, 4, 'var(--fig-' + c + ')', false),
        rest: el('line', { stroke: 'var(--fig-muted)', 'stroke-width': 1.5, 'stroke-dasharray': '3 2' }, svg),
        label: text(svg, 0, LOAD_TIP + LOAD_PX / 4 + 4, { 'font-weight': 600, fill: 'var(--fig-' + c + ')' })
      };
    });
    // The scale of sideways acceleration: where the tyres give up, where the wheels lift, and now.
    el('line', { x1: BAR_X0, y1: BAR_Y, x2: BAR_X1, y2: BAR_Y, stroke: 'var(--fig-grid)', 'stroke-width': 4 }, svg);
    for (var t = 0; t <= BAR_MAX; t += 5) {
      text(svg, barX(t), BAR_Y + 17, { 'text-anchor': 'middle', 'font-size': 10 }).textContent = t + (t === BAR_MAX ? ' m/s²' : '');
    }
    var slideMark = el('path', { fill: 'var(--fig-orange)' }, svg);
    var slideText = text(svg, 0, BAR_Y - 9, { fill: 'var(--fig-orange)', 'text-anchor': 'middle' });
    var tipMark = el('path', { fill: 'var(--fig-red)' }, svg);
    var tipText = text(svg, 0, BAR_Y - 9, { fill: 'var(--fig-red)', 'text-anchor': 'middle' });
    var nowMark = el('circle', { r: 5, cy: BAR_Y, fill: 'var(--fig-blue)', stroke: 'var(--surface)', 'stroke-width': 1.5 }, svg);

    var controls = document.createElement('div');
    controls.className = 'w-controls';
    function row(id, label, min, max, step, value) {
      return '<label for="' + uid + '-' + id + '">' + label + '</label>' +
        '<input id="' + uid + '-' + id + '" type="range" min="' + min + '" max="' + max + '" step="' + step +
        '" value="' + value + '"><output for="' + uid + '-' + id + '"></output>';
    }
    controls.innerHTML =
      row('a', 'Cornering (<i>a</i>)', 0, 15, 0.1, 8) +
      row('h', 'Height of the centre of mass (<i>h</i>)', 0.3, 2.2, 0.05, 0.5) +
      row('t', 'Track (<i>L</i>)', 1, 2.6, 0.05, 1.6) +
      row('mu', 'Tyre grip (<i>μ</i>)', 0.1, 1.2, 0.05, 1);
    root.appendChild(controls);
    function input(id) { return controls.querySelector('#' + uid + '-' + id); }
    function output(id) { return controls.querySelector('output[for="' + uid + '-' + id + '"]'); }
    var inA = input('a'), inH = input('h'), inT = input('t'), inMu = input('mu');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function update() {
      var a = parseFloat(inA.value), h = parseFloat(inH.value);
      var track = parseFloat(inT.value), mu = parseFloat(inMu.value);
      output('a').textContent = fmt(a, 1) + ' m/s² (' + fmt(a / G, 2) + ' g)';
      output('h').textContent = fmt(h, 2) + ' m';
      output('t').textContent = fmt(track, 2) + ' m';
      output('mu').textContent = fmt(mu, 2);

      var aGrip = mu * G, aLift = G * (track / 2) / h;
      var aNow = Math.min(a, aGrip);           // the tyres cannot give more
      var slides = a > aGrip && aGrip < aLift;
      var tips = aNow >= aLift;
      var shift = Math.min(aNow / G * h / (track / 2), 1); // load moved, as a share of half the weight

      // The vehicle, upright or tipped about its outside contact point.
      var wR = VEHICLES[current].wheel * S, wW = 0.26 * S, half = track / 2 * S;
      var top = GROUND - (h + Math.max(h, 0.9)) * S, floor = GROUND - Math.min(0.3, h - 0.12) * S;
      body.setAttribute('x', CX - half - 0.2 * S); body.setAttribute('width', 2 * half + 0.4 * S);
      body.setAttribute('y', top); body.setAttribute('height', floor - top);
      [CX - half, CX + half].forEach(function (x, i) {
        wheels[i].setAttribute('x', x - wW / 2); wheels[i].setAttribute('width', wW);
        wheels[i].setAttribute('y', GROUND - 2 * wR); wheels[i].setAttribute('height', 2 * wR);
      });
      var pivotX = CX + half + wW / 2, ang = tips ? TIP_DEG : 0, rad = ang * Math.PI / 180;
      veh.setAttribute('transform', 'rotate(' + ang + ' ' + pivotX + ' ' + GROUND + ')');
      var cx0 = CX - pivotX, cy0 = -h * S;
      var comX = pivotX + cx0 * Math.cos(rad) - cy0 * Math.sin(rad);
      var comY = GROUND + cx0 * Math.sin(rad) + cy0 * Math.cos(rad);
      com.setAttribute('transform', 'translate(' + comX + ',' + comY + ')');

      // Weight down, carrying on outwards, and the two added up; on the vehicle, the line of that
      // push runs from the centre of mass to the road.
      var fx = FORCE_PX * aNow / G;
      weight(IX, IY, IX, IY + FORCE_PX);
      carry(IX, IY, IX + fx, IY);
      both(IX, IY, IX + fx, IY + FORCE_PX);
      var hitX = comX + (GROUND - comY) * aNow / G;
      reach.setAttribute('x1', comX); reach.setAttribute('y1', comY);
      reach.setAttribute('x2', hitX); reach.setAttribute('y2', GROUND);
      land.setAttribute('cx', hitX); land.setAttribute('cy', GROUND);
      land.setAttribute('fill', tips ? 'var(--fig-red)' : 'var(--fig-ink)');

      [[CX - half, 1 - shift], [CX + half, 1 + shift]].forEach(function (d, i) {
        var o = loads[i], len = LOAD_PX * d[1] / 2, x = d[0];
        o.arrow(x, LOAD_TIP + len, x, LOAD_TIP);
        o.rest.setAttribute('x1', x - 9); o.rest.setAttribute('x2', x + 9);
        o.rest.setAttribute('y1', LOAD_TIP + LOAD_PX / 2); o.rest.setAttribute('y2', LOAD_TIP + LOAD_PX / 2);
        o.label.setAttribute('x', x + (i ? 12 : -12));
        o.label.setAttribute('text-anchor', i ? 'start' : 'end');
        o.label.textContent = i === 0 && shift >= 1 ? 'lifts' : fmt(d[1] * 50) + ' %';
      });

      // The scale: the lower of the two marks is what happens first.
      var tri = function (x) { return 'M' + x + ',' + (BAR_Y - 2) + ' l-5,-6 h10 Z'; };
      slideMark.setAttribute('d', tri(barX(aGrip)));
      slideText.setAttribute('x', barX(aGrip)); slideText.textContent = 'slides';
      tipMark.setAttribute('d', tri(barX(aLift)));
      tipText.setAttribute('x', barX(aLift)); tipText.textContent = aLift > BAR_MAX ? 'tips ›' : 'tips';
      // Two labels too close to read: the one further along moves above the other.
      var close = Math.abs(barX(aGrip) - barX(aLift)) < 40;
      slideText.setAttribute('y', close && aGrip > aLift ? BAR_Y - 22 : BAR_Y - 9);
      tipText.setAttribute('y', close && aLift >= aGrip ? BAR_Y - 22 : BAR_Y - 9);
      nowMark.setAttribute('cx', barX(aNow));

      var said = 'The tyres can give up to ' + fmt(aGrip, 1) + ' m/s² sideways, and the inside wheels lift at ' +
        fmt(aLift, 1) + ' m/s². ';
      said += tips ? '<strong>It tips:</strong> the combined push lands outside the outside wheels.'
        : slides ? '<strong>It slides:</strong> the tyres give up before the vehicle can tip.'
        : '<strong>It holds:</strong> the inside wheels still carry ' + fmt((1 - shift) * 50) + ' % of the weight.';
      // The point of no return: the lean that puts the centre of mass right above the outside wheels.
      said += ' Past a lean of <strong>' + fmt(Math.atan((track / 2) / h) * 180 / Math.PI) + '°</strong>, ' +
        'its centre of mass is above the outside wheels and it falls over even without the push.';
      readout.innerHTML = said;
      svg.setAttribute('aria-label', 'A vehicle from behind, turning left. ' + said.replace(/<[^>]+>/g, ''));
    }
    [inA, inH, inT, inMu].forEach(function (i) { i.addEventListener('input', update); });
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets.rollover = make;
})();
