// Sift: reports every URL change (including History API changes made by
// single-page apps) to the native router, and gives site scripts a hide helper.
(function () {
  if (window.__siftCommon) return;
  window.__siftCommon = true;

  var last = null;
  function report() {
    var href = location.href;
    if (href === last) return;
    last = href;
    try {
      window.webkit.messageHandlers.sift.postMessage({ type: 'url', href: href });
    } catch (e) {}
  }

  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function () {
      var result = original.apply(this, arguments);
      report();
      return result;
    };
  });
  window.addEventListener('popstate', report);
  window.addEventListener('hashchange', report);
  // Fallback for any change the hooks miss.
  setInterval(report, 400);

  // Page background color, so the app can paint the status bar and home
  // indicator strips to match the page.
  var lastColor = null;
  function opaque(c) {
    return c && c !== 'transparent' && !/rgba\([^)]*,\s*0\)$/.test(c);
  }
  function pageColor() {
    var metas = document.querySelectorAll('meta[name="theme-color"]');
    for (var i = 0; i < metas.length; i++) {
      var media = metas[i].getAttribute('media');
      if (!media || window.matchMedia(media).matches) {
        var c = metas[i].getAttribute('content');
        if (c) return c.trim();
      }
    }
    var els = [document.body, document.documentElement];
    for (var j = 0; j < els.length; j++) {
      if (!els[j]) continue;
      var bg = getComputedStyle(els[j]).backgroundColor;
      if (opaque(bg)) return bg;
    }
    return null;
  }
  function reportColor() {
    var c = pageColor();
    if (!c || c === lastColor) return;
    lastColor = c;
    try {
      window.webkit.messageHandlers.sift.postMessage({ type: 'color', value: c });
    } catch (e) {}
  }
  document.addEventListener('DOMContentLoaded', reportColor);
  window.addEventListener('load', reportColor);
  setInterval(reportColor, 1000);

  window.__siftHide = function (el) {
    if (el && el.style) el.style.setProperty('display', 'none', 'important');
  };

  // Runs fn now and again whenever the page adds content (at most every
  // 400 ms, so typing and scrolling stay smooth).
  window.__siftWatch = function (fn) {
    var queued = false;
    function run() {
      queued = false;
      try { fn(); } catch (e) {}
    }
    function queue() {
      if (queued) return;
      queued = true;
      setTimeout(run, 400);
    }
    queue();
    new MutationObserver(queue).observe(document, { childList: true, subtree: true });
  };
})();
