// Fuel burn against engine load: choose a road speed, a slope and a gear, and see how much fuel
// a saloon car burns, per hour and per 100 km, and where the fuel's energy goes. Plain JS and SVG,
// no libraries.
// Figures, all read from the simulator:
//   sedan_spec.tres     mass 1150 kg; wheel_radius 0.36 m; drag_area 0.65 m²; rolling_resistance
//                       0.012; gear_ratios 4.5 2.903 1.975 1.431 1.109 0.925; torque_curve as below;
//                       engine_friction_frac 0.07, engine_brake_frac 0.25
//   VehicleSpec         final_drive 3.9, efficiency 0.9, idle_rpm 900, redline_rpm 6800 (defaults,
//                       the sedan's); fuel_type PETROL
//   VehicleTelemetry    FUEL_INDICATED_EFFICIENCY 0.41, FUEL_HEATING_MJ_KG 41.05,
//                       FUEL_DENSITY_KG_L 0.757 (petrol)
//   VehicleMath         AIR_DENSITY 1.225; BrakeSizing.G 9.8
// The burn is VehicleTelemetry.fuel_rate_lph: the fuel's torque is the engine's net torque plus
// its friction (Drivetrain.motoring_torque, linear in rpm from 0.07 to 0.25 of the peak torque
// between idle and redline), and the fuel's power is that torque's power over 0.41. The load is
// steady driving (no acceleration): rolling resistance, air drag and the slope.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var MASS = 1150, R = 0.36, CDA = 0.65, CRR = 0.012, G = 9.8, RHO = 1.225;
  var RATIOS = [4.5, 2.903, 1.975, 1.431, 1.109, 0.925], FD = 3.9, EFF = 0.9;
  var IDLE = 900, RED = 6800;
  var CURVE = [[900, 98], [2000, 154], [3200, 184], [4800, 185], [6000, 185], [6600, 170], [6800, 61]];
  var PEAK_T = 185, FRIC_IDLE = 0.07, FRIC_RED = 0.25;
  var ETA = 0.41, LHV = 41.05e6, DENSITY = 0.757;
  var AUTO_MIN_RPM = 1200; // the gear the widget picks: the highest that keeps the engine above this
  var X0 = 52, X1 = 404, Y0 = 168, Y1 = 18, VMIN = 10, VMAX = 150;
  var BAR_Y = 236, BAR_H = 20;

  function torqueAt(rpm) {
    if (rpm <= CURVE[0][0]) return CURVE[0][1];
    for (var i = 1; i < CURVE.length; i++) {
      if (rpm <= CURVE[i][0]) {
        var t = (rpm - CURVE[i - 1][0]) / (CURVE[i][0] - CURVE[i - 1][0]);
        return CURVE[i - 1][1] + (CURVE[i][1] - CURVE[i - 1][1]) * t;
      }
    }
    return CURVE[CURVE.length - 1][1];
  }
  function friction(rpm) {
    var f = Math.min(1, Math.max(0, (rpm - IDLE) / (RED - IDLE)));
    return (FRIC_IDLE + (FRIC_RED - FRIC_IDLE) * f) * PEAK_T;
  }
  // One steady state. gear: 0-based, or -1 for idling in neutral at a standstill.
  function solve(kmh, slopePct, gear) {
    var v = kmh / 3.6;
    var th = Math.atan(slopePct / 100);
    var fRoll = CRR * MASS * G * Math.cos(th);
    var fSlope = MASS * G * Math.sin(th);
    var fAir = 0.5 * RHO * CDA * v * v;
    var pWheels = (fRoll + fSlope + fAir) * v;
    var rpm = IDLE, pEngine = 0;
    if (gear >= 0) {
      rpm = v / R * RATIOS[gear] * FD * 60 / (2 * Math.PI);
      if (rpm < IDLE) return { ok: false, why: 'low', rpm: rpm };
      if (rpm > RED) return { ok: false, why: 'high', rpm: rpm };
      pEngine = pWheels >= 0 ? pWheels / EFF : pWheels * EFF;
    }
    var omega = rpm * 2 * Math.PI / 60;
    var torque = pEngine / omega;
    if (torque > torqueAt(rpm)) return { ok: false, why: 'weak', rpm: rpm };
    var fric = friction(rpm);
    var fuelTorque = Math.max(0, torque + fric);
    var pChem = fuelTorque * omega / ETA;
    var lph = pChem / (LHV * DENSITY) * 3600;
    return {
      ok: true, rpm: rpm, kmh: kmh, gear: gear, pWheels: pWheels, pEngine: pEngine,
      pFric: fric * omega, pChem: pChem, lph: lph, l100: kmh > 0 ? lph / kmh * 100 : null,
      fAir: fAir, fRoll: fRoll, fSlope: fSlope, torque: torque
    };
  }
  function autoGear(kmh, slopePct) {
    if (kmh <= 0) return -1;
    var lowest = -1;
    for (var g = RATIOS.length - 1; g >= 0; g--) {
      var s = solve(kmh, slopePct, g);
      if (s.ok && s.rpm >= AUTO_MIN_RPM) return g;
      if (s.ok && lowest < 0) lowest = g;
    }
    return lowest;
  }
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
  function niceMax(x) {
    var steps = [10, 15, 20, 25, 30, 40, 50, 60, 80, 100];
    for (var i = 0; i < steps.length; i++) if (x <= steps[i]) return steps[i];
    return Math.ceil(x / 50) * 50;
  }
  function kw(w) { return (Math.abs(w) < 9500 ? (Math.round(w / 100) / 10).toFixed(1) : Math.round(w / 1000)) + ' kW'; }
  function pct(x) { return Math.round(x * 100) + ' %'; }

  function make(root) {
    root.innerHTML = '';
    var svg = el('svg', { viewBox: '0 0 420 286', role: 'img',
      'aria-label': 'Fuel burned per 100 km against road speed, with a marker at the chosen speed, and a bar showing where the fuel\'s energy goes' }, root);
    var px = function (k) { return X0 + (X1 - X0) * (k - VMIN) / (VMAX - VMIN); };
    var ymax = 10;
    var py = function (l) { return Y0 - (Y0 - Y1) * l / ymax; };

    var grid = el('g', {}, svg);
    el('path', { d: 'M' + X0 + ',' + (Y1 - 6) + ' L' + X0 + ',' + Y0 + ' L' + (X1 + 4) + ',' + Y0,
      fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    [10, 50, 100, 150].forEach(function (k) {
      text(svg, px(k), Y0 + 16, String(k), { 'text-anchor': k === 150 ? 'end' : 'middle' });
    });
    text(svg, (X0 + X1) / 2, Y0 + 32, 'road speed, km/h', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, 12, (Y0 + Y1) / 2, 'litres per 100 km', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600,
      transform: 'rotate(-90 12 ' + (Y0 + Y1) / 2 + ')' });
    var curve = el('polyline', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3, 'stroke-linejoin': 'round' }, svg);
    var marker = el('circle', { r: 6.5, fill: 'var(--fig-orange)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);

    // The energy bar: heat, engine friction, gearbox losses, the wheels.
    var SEGS = [
      { key: 'heat', name: 'heat', color: 'var(--fig-red)' },
      { key: 'fric', name: 'engine friction', color: 'var(--fig-orange)' },
      { key: 'gear', name: 'gears', color: 'var(--fig-muted)' },
      { key: 'wheels', name: 'wheels', color: 'var(--fig-blue)' }
    ];
    var barTitle = text(svg, X0 - 40, BAR_Y - 8, 'Where each litre\'s energy goes', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    var barW = X1 - (X0 - 40);
    // A fixed legend under the bar (swatch, name and share), so narrow segments never crowd it.
    var LEGEND_X = [10, 84, 232, 314];
    SEGS.forEach(function (s, i) {
      s.rect = el('rect', { y: BAR_Y, height: BAR_H, fill: s.color }, svg);
      el('rect', { x: LEGEND_X[i], y: BAR_Y + BAR_H + 8, width: 10, height: 10, fill: s.color }, svg);
      s.label = text(svg, LEGEND_X[i] + 14, BAR_Y + BAR_H + 17, '', { 'font-size': 12 });
    });
    var barNote = text(svg, X0 - 40, BAR_Y + 16, '', { fill: 'var(--fig-ink)' });

    var uid = 'fb' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-v">Speed</label><input id="' + uid + '-v" type="range" min="0" max="150" step="10" value="90">' +
      '<output for="' + uid + '-v"></output>' +
      '<label for="' + uid + '-s">Slope</label><input id="' + uid + '-s" type="range" min="-8" max="8" step="1" value="0">' +
      '<output for="' + uid + '-s"></output>' +
      '<label for="' + uid + '-g">Gear</label><input id="' + uid + '-g" type="range" min="1" max="6" step="1" value="6">' +
      '<output for="' + uid + '-g"></output>';
    root.appendChild(controls);
    var ins = controls.querySelectorAll('input');
    var vIn = ins[0], sIn = ins[1], gIn = ins[2];
    var outs = controls.querySelectorAll('output');
    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function drawCurve(slope) {
      var pts = [], top = 0, k, s;
      for (k = VMIN; k <= VMAX; k += 5) {
        var g = autoGear(k, slope);
        if (g < 0) { pts.push(null); continue; }
        s = solve(k, slope, g);
        pts.push([k, s.l100]);
        top = Math.max(top, s.l100);
      }
      return { pts: pts, top: top };
    }
    function drawGrid() {
      while (grid.firstChild) grid.removeChild(grid.firstChild);
      var step = ymax <= 10 ? 2 : ymax <= 30 ? 5 : ymax <= 60 ? 10 : 20;
      for (var l = 0; l <= ymax + 1e-6; l += step) {
        el('line', { x1: X0, y1: py(l), x2: X1, y2: py(l), stroke: 'var(--fig-grid)' }, grid);
        text(grid, X0 - 6, py(l) + 4, String(l), { 'text-anchor': 'end' });
      }
    }
    function drawBar(s) {
      var showBar = s && s.ok && s.pChem > 0 && s.pEngine >= 0;
      var parts = {};
      if (showBar) {
        parts.heat = 1 - ETA;
        parts.fric = s.pFric / s.pChem;
        parts.gear = (s.pEngine - s.pWheels) / s.pChem;
        parts.wheels = s.pWheels / s.pChem;
      }
      var x = X0 - 40;
      SEGS.forEach(function (seg) {
        var share = showBar ? Math.max(0, parts[seg.key]) : 0;
        var w = barW * share;
        seg.rect.setAttribute('x', x);
        seg.rect.setAttribute('width', w);
        seg.label.textContent = seg.name + (showBar ? ' ' + pct(share) : '');
        x += w;
      });
      barTitle.style.display = '';
      barNote.textContent = showBar ? '' : (s && s.ok && s.pChem <= 0
        ? 'Fuel cut: the slope drives the wheels and the engine.'
        : (s && s.ok ? 'Downhill: the slope pays part of the engine\'s friction.' : ''));
    }
    function update(fromGear) {
      var kmh = parseFloat(vIn.value), slope = parseFloat(sIn.value);
      if (!fromGear) {
        var ag = autoGear(kmh, slope);
        gIn.disabled = kmh <= 0;
        if (ag >= 0) gIn.value = String(ag + 1);
      }
      var gear = kmh <= 0 ? -1 : parseInt(gIn.value, 10) - 1;
      outs[0].textContent = kmh + ' km/h';
      outs[1].textContent = (slope > 0 ? '+' : '') + slope + ' %';
      outs[2].textContent = gear < 0 ? 'N' : String(gear + 1);

      var c = drawCurve(slope);
      var s = solve(kmh, slope, gear);
      ymax = niceMax(Math.max(c.top, s.ok && s.l100 ? s.l100 : 0, 1));
      drawGrid();
      curve.setAttribute('points', c.pts.filter(Boolean).map(function (p) { return px(p[0]) + ',' + py(p[1]); }).join(' '));
      var onPlot = s.ok && kmh >= VMIN;
      marker.style.display = onPlot ? '' : 'none';
      if (onPlot) { marker.setAttribute('cx', px(kmh)); marker.setAttribute('cy', py(Math.min(s.l100, ymax))); }
      drawBar(s);

      if (!s.ok) {
        readout.innerHTML = '<strong>' + (s.why === 'low'
          ? 'Gear ' + (gear + 1) + ' is too tall for ' + kmh + ' km/h: the engine would turn below idle.'
          : s.why === 'high'
            ? 'Gear ' + (gear + 1) + ' is too short for ' + kmh + ' km/h: the engine would pass its redline.'
            : 'In gear ' + (gear + 1) + ', the engine cannot give enough torque to hold ' + kmh + ' km/h on this slope.') +
          '</strong>';
        return;
      }
      var line1 = kmh <= 0
        ? 'Idling at a standstill: about ' + s.lph.toFixed(2) + ' litres an hour, just to keep the engine turning.'
        : s.lph < 0.05 ? 'No fuel at all: the slope keeps the car going, so the fuel is cut.'
          : 'About ' + s.lph.toFixed(1) + ' litres an hour, or ' + s.l100.toFixed(1) + ' litres per 100 km.';
      var line2 = kmh <= 0 ? 'The engine turns at ' + Math.round(s.rpm) + ' rpm and gives no power to the wheels.'
        : 'The engine turns at ' + Math.round(s.rpm) + ' rpm. ' + (s.pWheels > 0
          ? 'The wheels need ' + kw(s.pWheels) + ', of which the air takes ' + pct(s.fAir / (s.fAir + s.fRoll + s.fSlope)) +
            (slope > 0 ? ' and the climb ' + pct(s.fSlope / (s.fAir + s.fRoll + s.fSlope)) : '') + '.'
          : 'The slope pushes the car harder than the air and the tyres hold it back.');
      readout.innerHTML = '<strong>' + line1 + '</strong><br>' + line2;
    }
    vIn.addEventListener('input', function () { update(false); });
    sIn.addEventListener('input', function () { update(false); });
    gIn.addEventListener('input', function () { update(true); });
    update(false);
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['fuel-burn'] = make;
})();
