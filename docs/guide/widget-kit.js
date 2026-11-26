// Shared parts for the guide's widgets (widgets/*.js), loaded before guide.js:
//   GuideKit.vehiclePicker(parent, items, value, onPick): a row of small vehicle icons, one
//     radio group, in place of a drop-down; each name is its tooltip, with no label beside. items: [{ id, icon, name }], icon one of ICONS'
//     keys; onPick(id) runs on a change. Returns { set(id) }.
//   GuideKit.helpButton(parent): a "?" button and the pop-up it opens under parent, which the
//     caller fills (panel). A click elsewhere or Esc closes it. Returns { button, panel,
//     open(bool), isOpen() }.
//   GuideKit.limitsButton(root): the page's caveats for the widget, behind a warning button at its
//     bottom right (see the function). guide.js calls it after every widget it starts.
//   GuideKit.card(info, c): a clicked part's explanation, with its links and photo (see the function).
// Icons: 24-unit squares drawn with strokes in currentColor, vehicles facing right; the plane and
// the drone are seen from above.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  // [paths, circles [cx, cy, r]]
  var ICONS = {
    car: [['M4.8 16.5H2.5V13.6L5.5 12.8L8.3 9.2H15L18.4 12.8L21.5 13.6V16.5H19.2M14.8 16.5H9.2',
      'M5.5 12.8H18.4M11.7 9.2V12.8'], [[7, 17, 2.2], [17, 17, 2.2]]],
    sports: [['M4.8 16.5H2V14.2L5.5 13.2L9 10.5H14.5L18.5 13.2L22 14V16.5H19.2M14.8 16.5H9.2',
      'M5.5 13.2H18.5'], [[7, 17, 2.2], [17, 17, 2.2]]],
    suv: [['M4.8 16.5H2V12.5L4.5 11.5L6 7.5H17.5L20.5 11.5L22 12V16.5H19.2M14.8 16.5H9.2',
      'M4.5 11.5H20.5M12 7.5V11.5'], [[7, 17, 2.2], [17, 17, 2.2]]],
    race: [['M4.8 16.5H1.5V14.6L7 13.3L9.5 11.2H13L15 13.3L21 13.8V16.5H19.2M14.8 16.5H9.2',
      'M19.5 13.7V10.5H22.5'], [[7, 17, 2.2], [17, 17, 2.2]]],
    truck: [['M3 15.5H1.5V5.5H14.5V15.5M14.5 8.5H19L22 12V15.5H20M16 15.5H7', 'M16.5 8.5V12H22'],
      [[5, 17.3, 2], [18, 17.3, 2]]],
    semi: [['M16 15.5H13.5V5H20.5L22 8V15.5H21', 'M15.5 7.5H21V10H15.5Z', 'M2 13.8H13.5M5.5 13.8V12.4H10V13.8'],
      [[5.5, 17.3, 2.2], [10.5, 17.3, 2.2], [18.5, 17.3, 2.2]]],
    tractor: [['M4 10.5V3.5H11.5L12.5 10.5', 'M12.5 11.5H21V15', 'M17 11.5V7'],
      [[7, 16, 5], [7, 16, 1.6], [19, 18.5, 2.8]]],
    speedboat: [['M2 12.5H22L19 17.5H3.5Z', 'M9.5 12.5L12 9H15'], []],
    cruiser: [['M1.5 13H22.5L19.5 18.5H4Z', 'M6.5 13V9H14L16.5 13', 'M8.5 11H13'], []],
    sailboat: [['M3 15H21L18.5 19H5.5Z', 'M12 15V2.5', 'M12 3.5L19.5 13.5H12', 'M11 5L5.5 13.5H11'], []],
    plane: [['M2.5 12H19.5Q22 12 22 12.8Q22 13.5 19.5 13.5H2.5Z', 'M11 3L13 3L14.5 12.5L13 21.5H11L12 12.5Z',
      'M2.5 8.5L4.5 12.5L2.5 16.5'], []],
    drone: [['M7.5 7.5L16.5 16.5M16.5 7.5L7.5 16.5', 'M10 10H14V14H10Z'],
      [[6, 6, 3], [18, 6, 3], [6, 18, 3], [18, 18, 3]]],
    train: [['M2 16V8.5L5 6H20.5L22 8.5V16Z', 'M10 6L13 3L16 6M11 2.5H15', 'M5.5 9H10M13 9H17.5M2 12.5H22'],
      [[6, 17.8, 1.6], [10, 17.8, 1.6], [14, 17.8, 1.6], [18, 17.8, 1.6]]]
  };

  function svgIcon(key) {
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var g = document.createElementNS(NS, 'g');
    g.setAttribute('fill', 'none');
    g.setAttribute('stroke', 'currentColor');
    g.setAttribute('stroke-width', '1.5');
    g.setAttribute('stroke-linejoin', 'round');
    g.setAttribute('stroke-linecap', 'round');
    svg.appendChild(g);
    var icon = ICONS[key] || ICONS.car;
    icon[0].forEach(function (d) {
      var p = document.createElementNS(NS, 'path');
      p.setAttribute('d', d);
      g.appendChild(p);
    });
    icon[1].forEach(function (c) {
      var e = document.createElementNS(NS, 'circle');
      e.setAttribute('cx', c[0]); e.setAttribute('cy', c[1]); e.setAttribute('r', c[2]);
      g.appendChild(e);
    });
    return svg;
  }

  function vehiclePicker(parent, items, value, onPick) {
    var row = document.createElement('div');
    row.className = 'w-vehicles';
    row.setAttribute('role', 'radiogroup');
    row.setAttribute('aria-label', 'Vehicle');
    var buttons = items.map(function (it) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'w-veh';
      b.setAttribute('role', 'radio');
      b.setAttribute('aria-label', it.name);
      b.title = it.name;
      b.appendChild(svgIcon(it.icon));
      b.addEventListener('click', function () { pick(it.id, true); });
      row.appendChild(b);
      return b;
    });
    // Arrow keys move along the row, as in any radio group.
    row.addEventListener('keydown', function (e) {
      var step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (!step) return;
      e.preventDefault();
      var i = indexOf(value);
      var next = items[(i + step + items.length) % items.length];
      pick(next.id, true);
      buttons[indexOf(next.id)].focus();
    });
    function indexOf(id) {
      for (var i = 0; i < items.length; i++) if (items[i].id === id) return i;
      return 0;
    }
    function pick(id, fromUser) {
      var changed = id !== value;
      value = id;
      buttons.forEach(function (b, i) {
        var on = items[i].id === id;
        b.setAttribute('aria-checked', on ? 'true' : 'false');
        b.tabIndex = on ? 0 : -1;
      });
      if (fromUser && changed) onPick(id);
    }
    pick(value, false);
    parent.appendChild(row);
    return { set: function (id) { pick(id, false); } };
  }

  function helpButton(parent) {
    return popButton(parent, '?', 'Explain', false);
  }

  // The page's caveats for a widget: a `<div class="widget-limits" hidden>` right after the widget
  // moves into a pop-up behind a warning button at the widget's bottom right. No block, no button.
  function limitsButton(root) {
    var src = root.nextElementSibling;
    if (!src || !src.classList.contains('widget-limits')) return null;
    var foot = document.createElement('div');
    foot.className = 'w-foot';
    root.appendChild(foot);
    var pop = popButton(foot, null, 'What this drawing leaves out', true);
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    svg.innerHTML = '<path d="M12 3L22 20H2Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>' +
      '<path d="M12 9V14M12 16.8V17" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>';
    pop.button.appendChild(svg);
    while (src.firstChild) pop.panel.appendChild(src.firstChild);
    src.remove();
    return pop;
  }

  // A button and the pop-up it opens in parent: below it, or above it when up (for a footer).
  function popButton(parent, text, title, up) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'w-help';
    if (text) b.textContent = text;
    b.setAttribute('aria-label', title);
    b.title = title;
    var panel = document.createElement('div');
    panel.className = 'w-help-pop' + (up ? ' w-pop-up' : '');
    panel.id = 'wh' + Math.random().toString(36).slice(2, 8);
    panel.setAttribute('role', 'dialog');
    b.setAttribute('aria-controls', panel.id);
    parent.classList.add('w-help-host');
    function open(on) {
      panel.hidden = !on;
      b.setAttribute('aria-expanded', on ? 'true' : 'false');
    }
    b.addEventListener('click', function () { open(panel.hidden); });
    // A pop-up, not a panel: a click anywhere else or Esc closes it.
    function onPointer(e) {
      if (!document.contains(b)) { document.removeEventListener('pointerdown', onPointer); return; }
      if (!panel.hidden && !panel.contains(e.target) && e.target !== b) open(false);
    }
    document.addEventListener('pointerdown', onPointer);
    panel.addEventListener('keydown', function (e) { if (e.key === 'Escape') { open(false); b.focus(); } });
    b.addEventListener('keydown', function (e) { if (e.key === 'Escape') open(false); });
    open(false);
    parent.appendChild(b);
    parent.appendChild(panel);
    return { button: b, panel: panel, open: open, isOpen: function () { return !panel.hidden; } };
  }

  // A clickable widget's info card, filled into info: the name, one sentence, a link to the guide
  // page, a Wikipedia link, the signals line, and a credited photo on the right.
  // c: { name, text, page, pageTitle, wiki (article title, '#Section' allowed), sig (html),
  //      photo: { src, page (its Commons file page), author, licence } }; all but name and text optional.
  function card(info, c) {
    var html = '<strong>' + c.name + '.</strong> ' + c.text;
    if (c.page) html += ' <a href="#' + c.page + '">More: ' + c.pageTitle + '</a>';
    if (c.wiki) html += ' · <a href="https://en.wikipedia.org/wiki/' + c.wiki + '" target="_blank" rel="noopener">Wikipedia</a>';
    if (c.sig) html += '<span class="an-sig">' + c.sig + '</span>';
    var P = c.photo;
    if (P) {
      html = '<div class="w-card-text">' + html + '</div><figure class="w-photo"><img src="' + P.src +
        '" alt="Photo: ' + c.name + '" loading="lazy"><figcaption>Photo: <a href="' + P.page +
        '" target="_blank" rel="noopener">' + P.author + '</a>, ' + P.licence + '</figcaption></figure>';
    }
    info.classList.toggle('w-card', !!P);
    info.innerHTML = html;
  }

  window.GuideKit = { vehiclePicker: vehiclePicker, helpButton: helpButton, limitsButton: limitsButton, icon: svgIcon, card: card };
})();
