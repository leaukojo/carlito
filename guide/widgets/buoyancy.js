// Buoyancy against load: add weight to one of the game's hulls and see how deep the game's float
// law sinks it, and where the law runs out. Plain JS and SVG, no libraries.
// Figures, all read from the game:
//   boat.gd probe_force    each of the four probes pushes k x depth (plus a damper, 0 at rest),
//                          k = mass x g / (probes x float_depth), so the hull rests with every
//                          probe float_depth under water; capped at max_probe_force_factor 3.0 x
//                          the probe's weight share, so the four together hold at most 3 x the
//                          hull's own weight.
//   boat-speed-a_spec.tres mass 600, boat-speed-a.tscn float_depth 0.30, probes +-1.62 m
//   boat-speed-j_spec.tres mass 1400, boat-speed-j.tscn float_depth 0.34, probes +-2.05 m
//   boat-sail-a_spec.tres  mass 500, boat-sail-a.tscn float_depth 0.28, probes +-1.81 m
// The game's boats carry no cargo: the load here is a what-if on the same law. Water 1000 kg/m^3
// for the comparison with a real hull (Archimedes).
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var G = 9.81;
  var CAP = 3.0;
  var HULLS = [
    { name: 'boat-speed-a', mass: 600, depth: 0.30, half: 1.62 },
    { name: 'boat-speed-j', mass: 1400, depth: 0.34, half: 2.05 },
    { name: 'boat-sail-a', mass: 500, depth: 0.28, half: 1.81 }
  ];
  var SCALE = 60;       // px per metre in the drawing
  var WATER_Y = 110;
  var HULL_H = 0.9;     // drawn hull height (m), for the picture only

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
    title.textContent = 'Try it: buoyancy against load';
    root.appendChild(title);

    var svg = el('svg', { viewBox: '0 0 420 230', role: 'img', 'aria-label': 'A hull floating on the water line, sinking deeper as load is added' }, root);
    el('rect', { x: 0, y: WATER_Y, width: 420, height: 120, fill: 'var(--fig-blue)', opacity: 0.18 }, svg);
    el('line', { x1: 0, y1: WATER_Y, x2: 420, y2: WATER_Y, stroke: 'var(--fig-blue)', 'stroke-width': 2 }, svg);
    text(svg, 8, WATER_Y - 6, 'water line');
    var hull = el('path', { fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 2 }, svg);
    var load = el('rect', { fill: 'var(--fig-orange)', rx: 3 }, svg);
    var probes = [];
    for (var i = 0; i < 2; i++) {
      probes.push(el('circle', { r: 5, fill: 'var(--fig-blue)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg));
    }
    var depthLine = el('line', { stroke: 'var(--fig-ink)', 'stroke-width': 1.2, 'stroke-dasharray': '3 3' }, svg);
    var depthText = text(svg, 0, 0, '', { fill: 'var(--fig-ink)' });

    var uid = 'by' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-h">Hull</label><select id="' + uid + '-h"></select><span></span>' +
      '<label for="' + uid + '-l">Added load</label><input id="' + uid + '-l" type="range" min="0" max="3000" step="25" value="0">' +
      '<output for="' + uid + '-l"></output>';
    root.appendChild(controls);
    var sel = controls.querySelector('select');
    var slider = controls.querySelector('input');
    var out = controls.querySelector('output');
    HULLS.forEach(function (h, i) {
      var o = document.createElement('option');
      o.value = String(i);
      o.textContent = h.name;
      sel.appendChild(o);
    });

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);
    var note = document.createElement('p');
    note.className = 'w-note';
    note.textContent = 'The game\'s boats carry no cargo: this adds a load to the same law the game uses. The blue dots ' +
      'are two of the hull\'s four float points. The drawing\'s hull height is for the picture only.';
    root.appendChild(note);

    function update() {
      var h = HULLS[parseInt(sel.value, 10)];
      var extra = parseFloat(slider.value);
      var total = h.mass + extra;
      var maxHold = CAP * h.mass;
      var sinks = total > maxHold;
      // Each probe sinks until k x depth carries its share: depth = float_depth x total / mass.
      var d = sinks ? HULL_H + 0.4 : h.depth * total / h.mass;
      var len = 2 * h.half + 0.6;
      var x0 = 210 - len * SCALE / 2, x1 = 210 + len * SCALE / 2;
      var bottom = WATER_Y + d * SCALE;
      var top = bottom - HULL_H * SCALE;
      hull.setAttribute('d', 'M' + x0 + ',' + top + ' L' + x1 + ',' + top + ' L' + (x1 - 14) + ',' + bottom +
        ' L' + (x0 + 24) + ',' + bottom + ' Z');
      var lw = Math.min(len * SCALE - 60, 30 + extra / 15);
      var lh = Math.min(50, 8 + extra / 70);
      load.setAttribute('x', 210 - lw / 2); load.setAttribute('width', extra > 0 ? lw : 0);
      load.setAttribute('y', top - lh); load.setAttribute('height', extra > 0 ? lh : 0);
      var px = [210 - h.half * SCALE, 210 + h.half * SCALE];
      probes.forEach(function (p, i) { p.setAttribute('cx', px[i]); p.setAttribute('cy', bottom); });
      depthLine.setAttribute('x1', x1 + 14); depthLine.setAttribute('x2', x1 + 14);
      depthLine.setAttribute('y1', WATER_Y); depthLine.setAttribute('y2', Math.min(bottom, 228));
      depthText.setAttribute('x', Math.min(x1 + 20, 360)); depthText.setAttribute('y', Math.min((WATER_Y + bottom) / 2 + 4, 200));
      depthText.textContent = sinks ? '' : Math.round(d * 100) + ' cm';
      out.textContent = Math.round(extra) + ' kg';

      var volume = total / 1000;
      if (sinks) {
        readout.innerHTML = '<strong>It sinks.</strong> The four floats can push up at most ' + CAP +
          ' times the hull\'s own weight, ' + Math.round(maxHold) + ' kg in all, and the boat now weighs ' +
          Math.round(total) + ' kg.';
      } else {
        readout.innerHTML = '<strong>It floats ' + Math.round(d * 100) + ' cm deep at its float points.</strong><br>' +
          'Each of the four floats pushes up about ' + Math.round(total * G / 4) + ' N, a quarter of the boat\'s ' +
          Math.round(total) + ' kg. The game\'s law sinks the hull in proportion to its weight: twice the weight, twice as deep.<br>' +
          'A real hull would push aside ' + volume.toFixed(2) + ' m³ of water, the volume of water that weighs as much as the boat.';
      }
    }
    sel.addEventListener('change', function () { slider.max = String(2.5 * HULLS[parseInt(sel.value, 10)].mass); update(); });
    slider.addEventListener('input', update);
    slider.max = String(2.5 * HULLS[0].mass);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['buoyancy'] = make;
})();
