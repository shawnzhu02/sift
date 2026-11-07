// Sift: Instagram filters that CSS can't express (text-matched sections).
(function () {
  if (window.__siftInstagram) return;
  window.__siftInstagram = true;

  var hide = window.__siftHide;

  // Section headings whose whole block is recommended content.
  var BLOCKED_HEADINGS = ['suggested for you', 'suggested posts', 'more posts from', 'more reels'];

  function headingBlocked(text) {
    var t = (text || '').trim().toLowerCase();
    return BLOCKED_HEADINGS.some(function (h) { return t.indexOf(h) === 0; });
  }

  // Walk up to the nearest ancestor that also holds content besides the heading.
  function sectionFor(el) {
    var node = el;
    for (var i = 0; i < 6 && node.parentElement; i++) {
      node = node.parentElement;
      // Never hide the page itself, a profile header or a message box.
      if (node.matches('main, body, [role="main"]') || node.querySelector('main, header, textarea, [role="main"], [role="textbox"]')) {
        return el;
      }
      if (node.querySelector('a[href], img') && node.textContent.length > el.textContent.length + 20) {
        return node;
      }
    }
    return el;
  }

  function sweep() {
    // Profile Reels tab (also matched in CSS when it has role=tab).
    document.querySelectorAll('a[href$="/reels/"]').forEach(function (a) {
      var parts = a.getAttribute('href').split('/').filter(Boolean);
      if (parts.length === 2 && parts[1] === 'reels') hide(a);
    });

    // "Suggested for you" and similar recommendation blocks.
    document.querySelectorAll('h2, h3, h4, span, div[role="heading"]').forEach(function (el) {
      if (el.children.length > 2) return;
      if (headingBlocked(el.textContent)) hide(sectionFor(el));
    });

    // "Open app" / "Use the app" banners and buttons.
    document.querySelectorAll('a, button').forEach(function (el) {
      var t = (el.textContent || '').trim().toLowerCase();
      if (t === 'open app' || t === 'use the app' || t === 'get the app' || t === 'open instagram') hide(el);
    });
  }

  window.__siftWatch(sweep);
})();
