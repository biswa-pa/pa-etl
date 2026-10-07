// PA ETL branding inside the Prefect and Airbyte UIs. Colours live in the CSS files;
// this file handles what CSS cannot: the page title, icons, visible product names,
// and the Airbyte sidebar logo.
(function () {
  var BRAND = "PA ETL";
  var LABELS = { prefect: "Pipelines", airbyte: "Data sync" };

  // Prefect and Airbyte set their own titles ("Prefect Server", "Flows \u2022 Prefect Server").
  // A bare app title becomes "PA ETL \u00b7 Pipelines" / "PA ETL \u00b7 Data sync"; page titles keep
  // their page name and only swap the product name.
  function title() {
    var t = document.title || "";
    var bare = /^(prefect|airbyte)\b/i.exec(t);
    var next = bare && !/\u2022|\|/.test(t)
      ? BRAND + " \u00b7 " + LABELS[bare[1].toLowerCase()]
      : t.replace(/\bPrefect Server\b/g, BRAND).replace(/\b(Prefect|Airbyte)\b/g, BRAND);
    if (next !== t) document.title = next;
  }

  function icons() {
    var head = document.head;
    if (!head) return;
    document.querySelectorAll('link[rel~="icon"],link[rel="apple-touch-icon"],link[rel="mask-icon"],link[rel="shortcut icon"]').forEach(function (l) {
      l.parentNode.removeChild(l);
    });
    var i = document.createElement("link");
    i.rel = "icon";
    i.type = "image/png";
    i.href = "/__pa/icon.png";
    head.appendChild(i);
    var a = document.createElement("link");
    a.rel = "apple-touch-icon";
    a.href = "/__pa/apple-icon.png";
    head.appendChild(a);
  }

  // --- Visible product names ------------------------------------------------
  // "Prefect" and "Airbyte" (capitalised) become "PA ETL" in text the user reads.
  // Code, editors and form values are left alone so snippets such as
  // `from prefect import flow` and the user's own data stay correct.
  var NAMES = /\b(Prefect|Airbyte)\b/g;
  var HAS = /\b(Prefect|Airbyte)\b/;
  var SKIP_TAG = { SCRIPT: 1, STYLE: 1, TEXTAREA: 1, INPUT: 1, NOSCRIPT: 1, CODE: 1, PRE: 1, TITLE: 1 };
  var SKIP_CLOSEST = 'code,pre,textarea,input,[contenteditable="true"],.cm-editor,.monaco-editor,[class*="code" i],[class*="Code"]';
  var ATTRS = ["title", "alt", "aria-label", "placeholder"];

  function rebrand(s) { return s.replace(NAMES, BRAND); }

  function textOk(n) {
    var p = n.parentNode;
    if (!p || p.nodeType !== 1 || SKIP_TAG[p.tagName]) return false;
    return !(p.closest && p.closest(SKIP_CLOSEST));
  }

  function fixText(n) {
    var v = n.nodeValue;
    if (v && HAS.test(v) && textOk(n)) n.nodeValue = rebrand(v);
  }

  function fixAttrs(el) {
    for (var i = 0; i < ATTRS.length; i++) {
      var v = el.getAttribute && el.getAttribute(ATTRS[i]);
      if (v && HAS.test(v)) el.setAttribute(ATTRS[i], rebrand(v));
    }
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) return fixText(root);
    if (root.nodeType !== 1) return;
    fixAttrs(root);
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    var n;
    while ((n = w.nextNode())) {
      if (n.nodeType === 3) fixText(n);
      else fixAttrs(n);
    }
  }

  // React owns the original elements. Removing or replacing them can crash the app when it later
  // tries to unmount them, so the original is hidden and ours is inserted beside it. Our copy is
  // removed again once the original leaves the page.
  function overlay(node, src, css) {
    if (!node || !node.parentNode || node.getAttribute("data-pa-hidden")) return null;
    node.setAttribute("data-pa-hidden", "1");
    node.style.display = "none";
    var img = document.createElement("img");
    img.src = src;
    img.alt = BRAND;
    img.setAttribute("data-pa-overlay", "1");
    img.style.cssText = css;
    img._paFor = node;
    node.parentNode.insertBefore(img, node.nextSibling);
    return img;
  }

  function sweepOverlays() {
    document.querySelectorAll("img[data-pa-overlay]").forEach(function (img) {
      if (img._paFor && !img._paFor.isConnected) img.parentNode.removeChild(img);
    });
  }

  // --- Things to hide or swap -------------------------------------------------
  // Prefect V2 sidebar: drop the community link and replace the logo mark with ours.
  function prefectV2() {
    document.querySelectorAll('li[data-sidebar="menu-item"]').forEach(function (li) {
      if (/^\s*Join the community\s*$/i.test(li.textContent)) li.style.display = "none";
    });
    var svg = document.querySelector('[data-sidebar="header"] svg, [data-sidebar="sidebar"] a[href="/"] > svg');
    if (svg) overlay(svg, "/__pa/logo.svg", "display:block;height:34px;width:auto");
  }

  // Airbyte's sidebar logo is an inline SVG. Hide the first SVG that sits at the top of the
  // sidebar (above the menu list); do nothing if the layout is not recognised.
  function airbyteSidebarLogo() {
    var sb = document.querySelector('[class*="SideBar-module__sidebar__"]');
    if (!sb || sb.getAttribute("data-pa-logo")) return;
    var box = sb.getBoundingClientRect();
    var svgs = sb.querySelectorAll("svg");
    for (var i = 0; i < svgs.length; i++) {
      var r = svgs[i].getBoundingClientRect();
      if (svgs[i].closest("ul") || r.width < 20 || r.top - box.top > 90) continue;
      overlay(svgs[i], "/__pa/logo.svg", "display:block;height:30px;width:auto;margin:14px 12px 6px");
      sb.setAttribute("data-pa-logo", "1");
      return;
    }
  }

  // Sign-in page logo ("Airbyte" wordmark).
  function airbyteLoginLogo() {
    document.querySelectorAll('svg[class*="LoginPage-module__loginPage__logo"]').forEach(function (svg) {
      overlay(svg, "/__pa/logo-dark.svg", "display:block;height:40px;width:auto");
    });
  }

  // Page loader: an animated Airbyte logo (an SVG titled "Loading ..."). Replace large ones with
  // the animated PA ETL mark; small spinners inside buttons are only recoloured by the CSS.
  function airbyteLoader() {
    document.querySelectorAll("svg").forEach(function (svg) {
      if (svg.getAttribute("data-pa-hidden")) return;
      var t = svg.querySelector(":scope > title");
      if (!t || !/^\s*Loading/i.test(t.textContent)) return;
      var r = svg.getBoundingClientRect();
      if (r.width < 30) return;
      overlay(svg, "/__pa/mark-animated.svg", "display:block;width:" + Math.round(r.width) + "px;height:" + Math.round(r.height) + "px");
    });
  }

  // The "Connections link Sources to Destinations" illustration: put the PA ETL mark in the centre
  // tile and tint the glow orange and purple instead of Airbyte's blue and pink.
  function airbyteHero() {
    var NS = "http://www.w3.org/2000/svg";
    document.querySelectorAll('svg[class*="ConnectionOnboarding-module__illustration"]').forEach(function (svg) {
      if (svg.getAttribute("data-pa-hero")) return;
      var g = svg.querySelector("g[filter]");
      var logo = g && g.querySelector("path[fill-rule]");
      if (!g || !logo) return;
      svg.setAttribute("data-pa-hero", "1");
      logo.style.display = "none";
      var defs = document.createElementNS(NS, "defs");
      defs.innerHTML =
        '<radialGradient id="paGlow"><stop offset="0" stop-color="#fd9904" stop-opacity=".38"/>' +
        '<stop offset=".55" stop-color="#8b5cf6" stop-opacity=".16"/><stop offset="1" stop-color="#8b5cf6" stop-opacity="0"/></radialGradient>' +
        '<filter id="paShadow" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="14" stdDeviation="12" flood-color="#1a0a22" flood-opacity=".2"/></filter>';
      svg.insertBefore(defs, svg.firstChild);
      var glow = document.createElementNS(NS, "circle");
      glow.setAttribute("cx", "246"); glow.setAttribute("cy", "155"); glow.setAttribute("r", "125");
      glow.setAttribute("fill", "url(#paGlow)");
      svg.insertBefore(glow, g);
      g.setAttribute("filter", "url(#paShadow)");
      var mark = document.createElementNS(NS, "image");
      mark.setAttribute("href", "/__pa/mark-animated.svg");
      mark.setAttribute("x", "202"); mark.setAttribute("y", "111");
      mark.setAttribute("width", "88"); mark.setAttribute("height", "88");
      g.appendChild(mark);
    });
  }

  // --- Wiring -------------------------------------------------------------------
  var pending = [];
  var queued = false;

  function flush() {
    queued = false;
    var batch = pending;
    pending = [];
    for (var i = 0; i < batch.length; i++) walk(batch[i]);
    title();
    prefectV2();
    airbyteSidebarLogo();
    airbyteLoginLogo();
    airbyteLoader();
    airbyteHero();
    sweepOverlays();
  }

  function schedule(node) {
    if (node) pending.push(node);
    if (queued) return;
    queued = true;
    requestAnimationFrame(flush);
  }

  icons();
  title();
  function start() {
    walk(document.body);
    prefectV2();
    airbyteSidebarLogo();
    airbyteLoginLogo();
    airbyteLoader();
    airbyteHero();
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (r.type === "characterData") schedule(r.target);
        else if (r.type === "childList") for (var j = 0; j < r.addedNodes.length; j++) schedule(r.addedNodes[j]);
        else if (r.type === "attributes") schedule(r.target);
      }
      schedule(null);
    }).observe(document.documentElement, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRS,
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
