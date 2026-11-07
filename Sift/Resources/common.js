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

  window.__siftHide = function (el) {
    if (el && el.style) el.style.setProperty('display', 'none', 'important');
  };

  // Runs fn now and again whenever the page adds content (at most every
  // 150 ms, so typing in DMs stays smooth).
  window.__siftWatch = function (fn) {
    var queued = false;
    function run() {
      queued = false;
      try { fn(); } catch (e) {}
    }
    function queue() {
      if (queued) return;
      queued = true;
      setTimeout(run, 150);
    }
    queue();
    new MutationObserver(queue).observe(document, { childList: true, subtree: true });
  };
})();
