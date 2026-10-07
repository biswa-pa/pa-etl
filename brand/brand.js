// Small runtime touches for the PA ETL gateway. Colours live in the CSS files.
(function () {
  var BRAND = "PA ETL";
  var LABELS = { prefect: "Pipelines", airbyte: "Data sync" };

  // The original title tells us which app this is: "Prefect Server", "Airbyte ...".
  function title() {
    var m = /^(prefect|airbyte)/i.exec(document.title || "");
    if (m) document.title = BRAND + " \u00b7 " + LABELS[m[1].toLowerCase()];
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

  var queued = false;
  function tick() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; title(); });
  }

  icons();
  title();
  new MutationObserver(tick).observe(document.documentElement, { childList: true, subtree: true });
})();
