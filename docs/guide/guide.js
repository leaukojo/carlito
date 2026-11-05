// Carlito Mechanics Guide: a tiny static reader. The sidebar comes from pages.json, each page is a
// Markdown file rendered with the vendored marked (vendor/marked.min.js, v12). Routes are hashes:
// #tyres opens tyres.md, #tyres/slip-ratio opens it at that heading. Run it from a static server
// (npx serve docs/guide); browsers refuse fetch() on file:// pages.
(function () {
  'use strict';

  var content = document.getElementById('content');
  var sidebar = document.getElementById('sidebar');
  var menuButton = document.querySelector('.menu-button');
  var scrim = document.querySelector('.scrim');
  var themeButton = document.querySelector('.theme-button');

  var pages = [];          // [{file, title, group}], in pages.json order
  var glossary = {};       // slug -> plain-text definition, for link tooltips
  var widgetsLoading = {}; // widget name -> Promise
  var svgCache = {};       // svg path -> Promise<string>
  var current = null;      // id of the page on screen

  // ---- theme ------------------------------------------------------------------------------
  // The choice is system, light or dark; data-theme on <html> always holds the resolved light or
  // dark, so guide.css defines the dark tokens once. index.html resolves it before first paint.
  var THEMES = ['system', 'light', 'dark'];
  var systemDark = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function readTheme() {
    var t = 'system';
    try { t = localStorage.getItem('carlito-guide-theme') || 'system'; } catch (e) { /* blocked */ }
    return THEMES.indexOf(t) < 0 ? 'system' : t;
  }
  function resolveTheme(t) {
    return t === 'system' ? (systemDark && systemDark.matches ? 'dark' : 'light') : t;
  }
  function applyTheme(t) {
    document.documentElement.setAttribute('data-theme', resolveTheme(t));
    themeButton.querySelector('.theme-label').innerHTML = '<span class="theme-prefix">Theme: </span>' + t;
    try { localStorage.setItem('carlito-guide-theme', t); } catch (e) { /* not kept */ }
  }
  themeButton.addEventListener('click', function () {
    applyTheme(THEMES[(THEMES.indexOf(readTheme()) + 1) % THEMES.length]);
  });
  if (systemDark && systemDark.addEventListener) {
    systemDark.addEventListener('change', function () { if (readTheme() === 'system') applyTheme('system'); });
  }
  applyTheme(readTheme());

  // ---- sidebar drawer (phone width) -------------------------------------------------------
  function setMenu(open) {
    document.body.classList.toggle('menu-open', open);
    menuButton.setAttribute('aria-expanded', open ? 'true' : 'false');
    scrim.hidden = !open;
  }
  menuButton.addEventListener('click', function () {
    setMenu(!document.body.classList.contains('menu-open'));
  });
  scrim.addEventListener('click', function () { setMenu(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setMenu(false); });

  // ---- helpers ----------------------------------------------------------------------------
  function slugify(text) {
    return String(text).toLowerCase()
      .replace(/<[^>]*>/g, '')
      .replace(/&[a-z]+;|&#\d+;/g, '')
      .replace(/[^a-z0-9\s-]/g, '')
      .trim().replace(/\s+/g, '-').replace(/-+/g, '-');
  }
  function idOf(file) { return file.replace(/\.md$/, ''); }
  function pageById(id) {
    for (var i = 0; i < pages.length; i++) if (idOf(pages[i].file) === id) return pages[i];
    return null;
  }
  function parseHash() {
    var h = location.hash.replace(/^#/, '');
    try { h = decodeURIComponent(h); } catch (e) { /* a malformed escape: use it as written */ }
    var slash = h.indexOf('/');
    return slash < 0 ? { page: h || 'index', at: '' } : { page: h.slice(0, slash) || 'index', at: h.slice(slash + 1) };
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  // ---- markdown ---------------------------------------------------------------------------
  // Headings get stable ids from their text, so links like glossary.md#slip-ratio land.
  marked.use({
    gfm: true,
    renderer: {
      heading: function (text, level, raw) {
        var id = slugify(raw);
        return '<h' + level + ' id="' + id + '"><a class="anchor" href="#' + id + '" aria-hidden="true" tabindex="-1">#</a>' +
          text + '</h' + level + '>\n';
      }
    }
  });

  // Rewrites links between pages into hash routes: tyres.md -> #tyres, glossary.md#x -> #glossary/x,
  // #x -> #<this page>/x. External links open in a new tab.
  function rewriteLinks(root, pageId) {
    root.querySelectorAll('a[href]').forEach(function (a) {
      var href = a.getAttribute('href');
      if (/^(https?:)?\/\//.test(href) || /^mailto:/.test(href)) {
        a.setAttribute('target', '_blank');
        a.setAttribute('rel', 'noopener');
        return;
      }
      var m = /^([\w.-]+)\.md(?:#(.*))?$/.exec(href);
      if (m) {
        a.setAttribute('href', '#' + m[1] + (m[2] ? '/' + m[2] : ''));
        if (m[1] === 'glossary' && m[2]) {
          a.classList.add('term');
          a.setAttribute('data-term', m[2]);
        }
        return;
      }
      if (href.charAt(0) === '#') a.setAttribute('href', '#' + pageId + '/' + href.slice(1));
    });
    applyTermTitles(root);
  }
  // Hover text on term links, once the glossary has arrived (it loads beside the first page).
  function applyTermTitles(root) {
    root.querySelectorAll('a[data-term]').forEach(function (a) {
      var def = glossary[a.getAttribute('data-term')];
      if (def) a.setAttribute('title', def);
    });
  }
  // Tables scroll sideways inside a wrapper on a narrow screen, so they keep their table role.
  function wrapTables(root) {
    root.querySelectorAll('.page table').forEach(function (t) {
      var wrap = document.createElement('div');
      wrap.className = 'table-wrap';
      t.parentNode.insertBefore(wrap, t);
      wrap.appendChild(t);
    });
  }

  // A paragraph holding only an image becomes a figure; the image title is its caption. SVG
  // figures are inlined so they follow the page's light or dark colours.
  function upgradeFigures(root) {
    var jobs = [];
    root.querySelectorAll('p > img').forEach(function (img) {
      var p = img.parentNode;
      if (p.childNodes.length !== 1) return;
      var fig = document.createElement('figure');
      var caption = img.getAttribute('title');
      img.removeAttribute('title');
      p.parentNode.replaceChild(fig, p);
      fig.appendChild(img);
      if (caption) {
        var fc = document.createElement('figcaption');
        fc.textContent = caption;
        fig.appendChild(fc);
      }
      var src = img.getAttribute('src');
      if (/\.svg$/.test(src)) jobs.push(inlineSvg(img, src));
    });
    return Promise.all(jobs);
  }
  function inlineSvg(img, src) {
    if (!svgCache[src]) {
      svgCache[src] = fetch(src).then(function (r) {
        if (!r.ok) throw new Error(src + ': ' + r.status);
        return r.text();
      });
    }
    return svgCache[src].then(function (text) {
      var holder = document.createElement('div');
      holder.innerHTML = text;
      var svg = holder.querySelector('svg');
      if (!svg) return;
      svg.setAttribute('role', 'img');
      svg.setAttribute('aria-label', img.getAttribute('alt') || '');
      svg.classList.add('figure-svg');
      img.parentNode.replaceChild(svg, img);
    }).catch(function () { /* keep the <img>; it still shows */ });
  }

  // <div class="widget" data-widget="name"></div> loads widgets/name.js once, which registers
  // window.GuideWidgets[name] = function (element) { ... }.
  function startWidgets(root) {
    root.querySelectorAll('[data-widget]').forEach(function (el) {
      var name = el.getAttribute('data-widget');
      if (!/^[\w-]+$/.test(name)) return;
      if (!widgetsLoading[name]) {
        widgetsLoading[name] = new Promise(function (resolve, reject) {
          var s = document.createElement('script');
          s.src = 'widgets/' + name + '.js';
          s.onload = resolve;
          s.onerror = reject;
          document.head.appendChild(s);
        });
      }
      widgetsLoading[name].then(function () {
        var make = window.GuideWidgets && window.GuideWidgets[name];
        if (make) make(el);
      }).catch(function () {
        el.textContent = 'This interactive figure could not load (widgets/' + name + '.js).';
      });
    });
  }

  // ---- sidebar ----------------------------------------------------------------------------
  // Pages sorted by their group's place in `groups` (unlisted groups after, in first-seen order),
  // keeping file order inside a group. Stable, so appending an entry never reshuffles the rest.
  function orderByGroup(list, groups) {
    var rank = {};
    groups.forEach(function (g, i) { rank[g] = i; });
    var next = groups.length;
    list.forEach(function (p) { if (!(p.group in rank)) rank[p.group] = next++; });
    return list.map(function (p, i) { return { p: p, i: i }; })
      .sort(function (a, b) { return rank[a.p.group] - rank[b.p.group] || a.i - b.i; })
      .map(function (x) { return x.p; });
  }
  function buildSidebar() {
    var html = '';
    var group = null;
    pages.forEach(function (p) {
      if (p.hidden) return;
      if (p.group !== group) {
        if (group !== null) html += '</ul>';
        group = p.group;
        html += '<h2 class="nav-group">' + escapeHtml(group) + '</h2><ul>';
      }
      html += '<li><a href="#' + idOf(p.file) + '" data-page="' + idOf(p.file) + '">' +
        escapeHtml(p.title) + '</a></li>';
    });
    if (group !== null) html += '</ul>';
    sidebar.innerHTML = html;
  }
  function markCurrent(id) {
    sidebar.querySelectorAll('a[data-page]').forEach(function (a) {
      if (a.getAttribute('data-page') === id) a.setAttribute('aria-current', 'page');
      else a.removeAttribute('aria-current');
    });
  }
  function pager(id) {
    var visible = pages.filter(function (p) { return !p.hidden; });
    var i = -1;
    for (var k = 0; k < visible.length; k++) if (idOf(visible[k].file) === id) i = k;
    if (i < 0) return '';
    var prev = visible[i - 1], next = visible[i + 1];
    return '<nav class="pager" aria-label="Previous and next page">' +
      (prev ? '<a class="prev" href="#' + idOf(prev.file) + '"><span>Previous</span>' + escapeHtml(prev.title) + '</a>' : '<span></span>') +
      (next ? '<a class="next" href="#' + idOf(next.file) + '"><span>Next</span>' + escapeHtml(next.title) + '</a>' : '<span></span>') +
      '</nav>';
  }

  // ---- routing ----------------------------------------------------------------------------
  function scrollToAnchor(at) {
    var target = at ? document.getElementById(at) : null;
    if (target) target.scrollIntoView();
    else window.scrollTo(0, 0);
  }
  // Each navigation takes a number; a fetch that resolves after a newer navigation is dropped, so
  // a slow page can never replace the one the reader moved on to.
  var showSeq = 0;
  function show() {
    var seq = ++showSeq;
    var route = parseHash();
    setMenu(false);
    if (route.page === current) { scrollToAnchor(route.at); return; }
    var page = pageById(route.page);
    if (!page) {
      content.innerHTML = '<h1>Page not found</h1><p>No page is called "' + escapeHtml(route.page) +
        '". Pick one from the list.</p>';
      current = null;
      markCurrent('');
      return;
    }
    fetch(page.file).then(function (r) {
      if (!r.ok) throw new Error(page.file + ': ' + r.status);
      return r.text();
    }).then(function (md) {
      if (seq !== showSeq) return;
      var id = idOf(page.file);
      content.innerHTML = '<article class="page page-' + id + '">' + marked.parse(md) + '</article>' + pager(id);
      rewriteLinks(content, id);
      wrapTables(content);
      current = id;
      markCurrent(id);
      document.title = page.title + ' | Carlito Mechanics Guide';
      startWidgets(content);
      return upgradeFigures(content).then(function () { if (seq === showSeq) scrollToAnchor(route.at); });
    }).catch(function (err) {
      if (seq !== showSeq) return;
      content.innerHTML = '<h1>This page could not load</h1><p>' + escapeHtml(err.message) +
        '</p><p>The guide must be opened through a web server, not as a file. From the repository: ' +
        '<code>npx serve docs/guide</code>, then open the address it prints.</p>';
      current = null;
    });
  }

  // Glossary definitions become hover text on term links: the first paragraph under each heading.
  function loadGlossary() {
    return fetch('glossary.md').then(function (r) { return r.ok ? r.text() : ''; }).then(function (md) {
      var tokens = marked.lexer(md);
      var slug = null;
      tokens.forEach(function (t) {
        if (t.type === 'heading' && t.depth === 3) slug = slugify(t.text);
        else if (slug && t.type === 'paragraph') {
          var div = document.createElement('div');
          div.innerHTML = marked.parseInline(t.text);
          glossary[slug] = div.textContent.replace(/\s+/g, ' ').trim();
          slug = null;
        }
      });
    }).catch(function () { /* tooltips are a convenience */ });
  }

  // A link to the address already in the bar fires no hashchange; scroll to its target anyway.
  content.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('a[href^="#"]') : null;
    if (a && a.getAttribute('href') === location.hash) scrollToAnchor(parseHash().at);
  });

  // The glossary (for hover text only) loads beside the first page instead of ahead of it.
  var glossaryReady = loadGlossary();
  fetch('pages.json').then(function (r) {
    if (!r.ok) throw new Error('pages.json: ' + r.status);
    return r.json();
  }).then(function (list) {
    pages = orderByGroup(list.pages, list.groups || []);
    buildSidebar();
    window.addEventListener('hashchange', show);
    show();
    glossaryReady.then(function () { applyTermTitles(content); });
  }).catch(function (err) {
    content.innerHTML = '<h1>The guide could not start</h1><p>' + escapeHtml(err.message) +
      '</p><p>Open it through a web server: <code>npx serve docs/guide</code>.</p>';
  });
})();
