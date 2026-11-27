// Off-tracking: a truck or tractor with its trailer in a steady, slow turn, seen from above. Pick
// the rig, the radius of the circle the front wheels follow and the trailer's length, and see the
// circle each axle follows: the trailer's axles run inside the front wheels' circle, and the angle
// between the two bodies. Plain JS and SVG, no libraries.
// Geometry (low speed, no tyre slip: every axle points square to its radius from one centre):
//   rear axle radius  R_r = sqrt(R_f^2 - L^2)       L the wheelbase, R_f the front axle's radius
//   hitch radius      R_k = sqrt(R_r^2 + c^2)       c the hitch's distance ahead of the rear axle
//   trailer axle      R_t = sqrt(R_k^2 - L_t^2)     L_t from the hitch to the trailer's axles
//   articulation      atan(L_t / R_t) - atan(c / R_r)
// Figures, all read from the simulator:
//   semi_spec.tres            wheel_positions: steer axle z -2.65, drive axle z 0.95 (wheelbase
//                             3.60); max_steer_deg 24; body z -3.74 .. 1.71, 1.92 wide
//   fifth_wheel.gd            KINGPIN_LOCAL z 0.45: 0.50 m ahead of the drive axle
//   box_spec.tres             tri-axle bogie z 4.40 / 5.20 / 6.00 behind the kingpin: its middle
//                             5.20; the box about 7.3 m long (box.tscn rails 7.26)
//   Articulation.JACKKNIFE_MAX_DEG 75 (the trailer meeting the cab)
//   tractor-kenney_spec.tres  wheel_positions: front axle z -1.227, rear axle z 1.353 (wheelbase
//                             2.58); max_steer_deg 38
//   drawbar.gd                PIN_LOCAL z 2.41: 1.06 m behind the rear axle; SWING_MAX_DEG 57
//                             (the tipper body's corner meeting the rear tyre)
//   farm_tipper_spec.tres     tandem bogie z 3.30 / 3.95 behind the eye: its middle 3.625; the body
//                             from 1.09 m behind the eye (drawbar.gd), 3.86 long (farm_tipper.tscn)
// The smallest radius is the front axle's at full lock in the bicycle model, L / sin(max steer).
// Outlines are drawn to about the bodies' size; the paths are computed.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var RIGS = [
    { id: 'semi', icon: 'semi', name: 'Semi truck and box trailer', L: 3.60, c: 0.50, Lt: 5.20,
      steer: 24, stop: 75, ltMin: 3, ltMax: 12,
      cab: { front: 1.09 + 3.60, rear: -0.76, w: 1.92 },        // from the drive axle
      trl: { front: -0.8, overhang: 1.3, w: 1.9 },             // from the kingpin
      scale: 24, cabName: 'the cab', stopWhat: 'the trailer\'s front corner would meet the back of the cab' },
    { id: 'tractor', icon: 'tractor', name: 'Farm tractor and tipper trailer', L: 2.58, c: -1.06, Lt: 3.625,
      steer: 38, stop: 57, ltMin: 2, ltMax: 8,
      cab: { front: 2.58 + 1.0, rear: -0.75, w: 1.95 },
      trl: { front: 1.09, overhang: 1.33, w: 1.8 },
      scale: 30, cabName: 'the tractor', stopWhat: 'the trailer\'s front corner would hit the tractor\'s rear tyre' }
  ];
  var R_MAX = 40;

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
  function deg(r) { return r * 180 / Math.PI; }
  function rad(d) { return d * Math.PI / 180; }
  function rMin(rig) { return rig.L / Math.sin(rad(rig.steer)); }

  function make(root) {
    root.innerHTML = '';
    var rig = RIGS[0];
    GuideKit.vehiclePicker(root, RIGS.map(function (x) {
      return { id: x.id, icon: x.icon, name: x.name };
    }), rig.id, function (id) {
      for (var i = 0; i < RIGS.length; i++) if (RIGS[i].id === id) setRig(RIGS[i]);
    });

    var svg = el('svg', { viewBox: '0 0 420 270', role: 'img',
      'aria-label': 'Seen from above, the rig turning right, with the circle its front wheels follow and the smaller circle its trailer\'s axles follow' }, root);
    var pathF = el('circle', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3 }, svg);
    var pathR = el('circle', { fill: 'none', stroke: 'var(--fig-muted)', 'stroke-width': 1.2, 'stroke-dasharray': '5 4' }, svg);
    var pathT = el('circle', { fill: 'none', stroke: 'var(--fig-orange)', 'stroke-width': 3 }, svg);
    var centre = el('g', {}, svg);
    el('path', { d: 'M-6,0 L6,0 M0,-6 L0,6', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, centre);
    var trailer = el('polygon', { fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5, 'stroke-linejoin': 'round' }, svg);
    var cab = el('polygon', { fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5, 'stroke-linejoin': 'round' }, svg);
    var axleF = el('line', { stroke: 'var(--fig-blue)', 'stroke-width': 4, 'stroke-linecap': 'round' }, svg);
    var axleR = el('line', { stroke: 'var(--fig-ink)', 'stroke-width': 4, 'stroke-linecap': 'round' }, svg);
    var axleT = el('line', { stroke: 'var(--fig-orange)', 'stroke-width': 4, 'stroke-linecap': 'round' }, svg);
    var hitch = el('circle', { r: 3.5, fill: 'var(--fig-ink)' }, svg);
    text(svg, 12, 22, 'front wheels', { fill: 'var(--fig-blue)', 'font-weight': 600 });
    text(svg, 12, 40, 'trailer\'s axles', { fill: 'var(--fig-orange)', 'font-weight': 600 });

    var uid = 'ot' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-r">Turn radius</label><input id="' + uid + '-r" type="range" step="0.1">' +
      '<output for="' + uid + '-r"></output>' +
      '<label for="' + uid + '-t">Trailer length</label><input id="' + uid + '-t" type="range" step="0.1">' +
      '<output for="' + uid + '-t"></output>';
    root.appendChild(controls);
    var rIn = controls.querySelectorAll('input')[0];
    var tIn = controls.querySelectorAll('input')[1];
    var outs = controls.querySelectorAll('output');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    // World metres, y down the page like the screen: the rear axle at (0, 0) heading +x, the turn's
    // centre at (0, R_r), so the rig turns right.
    // Scale and place the drawing so the whole rig fits at its tightest turn (`layout`, on a change
    // of rig or trailer length; the radius only moves things within it).
    var S = 24, OX = 300, OY = 64;
    function sx(x) { return OX + x * S; }
    function sy(y) { return OY + y * S; }
    function articulation(rf, lt) {
      var rr = Math.sqrt(rf * rf - rig.L * rig.L);
      var rk = Math.sqrt(rr * rr + rig.c * rig.c);
      if (lt >= rk) return 180;
      return deg(Math.atan2(lt, Math.sqrt(rk * rk - lt * lt)) - Math.atan2(rig.c, rr));
    }
    function layout(lt) {
      var rear = lt + rig.trl.overhang, hw = rig.trl.w / 2;
      var worst = rad(Math.min(rig.stop, articulation(parseFloat(rIn.min), lt)));
      var lenX = rig.cab.front - (rig.c - rear);
      var drop = rear * Math.sin(worst) + hw * Math.cos(worst);
      S = Math.min(rig.scale, 396 / lenX, (270 - OY - 8) / Math.max(drop, rig.cab.w / 2));
      OX = 410 - rig.cab.front * S;
    }
    function pts(list) { return list.map(function (p) { return sx(p[0]) + ',' + sy(p[1]); }).join(' '); }
    function line(node, a, b) {
      node.setAttribute('x1', sx(a[0])); node.setAttribute('y1', sy(a[1]));
      node.setAttribute('x2', sx(b[0])); node.setAttribute('y2', sy(b[1]));
    }

    function update() {
      var rf = parseFloat(rIn.value), lt = parseFloat(tIn.value);
      if (lt !== laidOut) { layout(lt); laidOut = lt; }
      var rr = Math.sqrt(rf * rf - rig.L * rig.L);
      var rk = Math.sqrt(rr * rr + rig.c * rig.c);
      var rt = lt < rk ? Math.sqrt(rk * rk - lt * lt) : 0;
      var art = articulation(rf, lt);
      var folds = art > rig.stop;
      // Past the stop, the trailer is drawn at the stop: no steady turn exists there.
      var drawn = folds ? rig.stop : art;
      outs[0].textContent = rf.toFixed(1) + ' m';
      outs[1].textContent = lt.toFixed(1) + ' m';

      var cx = 0, cy = rr;
      [[pathF, rf], [pathR, rr], [pathT, rt]].forEach(function (p) {
        p[0].setAttribute('cx', sx(cx)); p[0].setAttribute('cy', sy(cy));
        p[0].setAttribute('r', Math.max(p[1], 0) * S);
      });
      pathT.style.display = folds ? 'none' : '';
      centre.setAttribute('transform', 'translate(' + sx(cx) + ',' + sy(cy) + ')');

      var hw = rig.cab.w / 2;
      cab.setAttribute('points', pts([[rig.cab.rear, -hw], [rig.cab.front, -hw], [rig.cab.front, hw], [rig.cab.rear, hw]]));
      var steer = Math.atan2(rig.L, rr);
      var half = 0.9;
      line(axleF, [rig.L + Math.sin(steer) * half, -Math.cos(steer) * half], [rig.L - Math.sin(steer) * half, Math.cos(steer) * half]);
      line(axleR, [0, -half], [0, half]);

      // The trailer points back from the hitch at the drawn angle, its tail swung inside the turn.
      var k = [rig.c, 0];
      var a = rad(drawn);
      var ux = Math.cos(a), uy = -Math.sin(a);           // unit vector from the axle to the hitch
      var nx = -uy, ny = ux;                             // its left-hand normal
      function at(z, side) { return [k[0] - ux * z + nx * side, k[1] - uy * z + ny * side]; }
      var tw = rig.trl.w / 2, rear = lt + rig.trl.overhang;
      trailer.setAttribute('points', pts([at(rig.trl.front, -tw), at(rear, -tw), at(rear, tw), at(rig.trl.front, tw)]));
      line(axleT, at(lt, -half), at(lt, half));
      hitch.setAttribute('cx', sx(k[0])); hitch.setAttribute('cy', sy(k[1]));

      if (folds) {
        readout.innerHTML = '<strong>Too tight for this trailer.</strong><br>' +
          'There is no steady turn here: the trailer keeps swinging round, and ' + rig.stopWhat +
          ' at about ' + rig.stop + '°.';
        return;
      }
      readout.innerHTML =
        '<strong>The trailer\'s axles run ' + (rf - rt).toFixed(1) + ' m inside the front wheels.</strong><br>' +
        'The front wheels follow a circle of ' + rf.toFixed(1) + ' m, ' + rig.cabName + '\'s rear axle one of ' +
        rr.toFixed(1) + ' m and the trailer\'s axles one of ' + rt.toFixed(1) + ' m.<br>' +
        'The angle between ' + rig.cabName + ' and the trailer: about ' + Math.round(art) + '°.';
    }
    var laidOut = -1;
    function setRig(chosen) {
      rig = chosen;
      laidOut = -1;
      var lo = Math.ceil(rMin(rig) * 10) / 10;
      rIn.min = String(lo); rIn.max = String(R_MAX);
      rIn.value = String(Math.max(lo, 12));
      tIn.min = String(rig.ltMin); tIn.max = String(rig.ltMax); tIn.value = String(rig.Lt);
      update();
    }
    rIn.addEventListener('input', update);
    tIn.addEventListener('input', update);
    setRig(rig);
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['off-tracking'] = make;
})();
