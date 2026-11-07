// Sift: swipe left or right on the page to switch between Messages,
// Subscriptions and Settings. Only clear horizontal flicks count, and never
// ones that start on something that already uses horizontal gestures.
(function (root) {
  var MIN_DX = 70;        // px the finger must travel sideways
  var RATIO = 2.2;        // sideways travel must beat vertical travel by this much
  var MAX_MS = 600;       // slower drags are scrolling or reading, not a flick
  var EDGE = 24;          // px at each screen edge left to WebKit's back/forward swipe

  // Pages where horizontal gestures belong to the page (stories, single reels).
  var PAGE_GESTURE_PATHS = [/^\/stories\//, /^\/reels?\//, /^\/[^/]+\/reels?\//];

  // Pure decision, so it can be tested without a browser.
  // Returns 'next', 'prev' or null.
  function decide(g) {
    if (g.touches !== 1) return null;
    if (g.blocked || g.selection) return null;
    if (g.startX <= EDGE || g.startX >= g.viewportWidth - EDGE) return null;
    if (PAGE_GESTURE_PATHS.some(function (re) { return re.test(g.path || ''); })) return null;
    if (g.dt > MAX_MS) return null;
    var ax = Math.abs(g.dx), ay = Math.abs(g.dy);
    if (ax < MIN_DX || ax < RATIO * ay) return null;
    // Finger moving left shows the next page, like turning a page.
    return g.dx < 0 ? 'next' : 'prev';
  }

  root.__siftSwipeDecision = decide;

  if (typeof document === 'undefined' || root.__siftSwipe) return;
  root.__siftSwipe = true;

  var NO_SWIPE = 'input, textarea, select, [contenteditable=""], [contenteditable="true"], video, ' +
    '[role="slider"], [role="textbox"], .html5-video-player, #player, ytm-player';

  // True when the touch starts on something that scrolls or slides sideways.
  function blockedTarget(el) {
    if (!el || !el.closest) return false;
    if (el.closest(NO_SWIPE)) return true;
    for (var node = el; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
      if (node.scrollWidth > node.clientWidth + 4) {
        var ox = getComputedStyle(node).overflowX;
        if (ox === 'auto' || ox === 'scroll' || ox === 'hidden') return true;
      }
    }
    return false;
  }

  var start = null;

  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) { start = null; return; }
    var t = e.touches[0];
    start = { x: t.clientX, y: t.clientY, time: Date.now(), blocked: blockedTarget(e.target) };
  }, { passive: true, capture: true });

  document.addEventListener('touchmove', function (e) {
    if (start && e.touches.length !== 1) start = null;  // pinch or two fingers
  }, { passive: true, capture: true });

  document.addEventListener('touchend', function (e) {
    if (!start || e.changedTouches.length !== 1) { start = null; return; }
    var t = e.changedTouches[0];
    var sel = window.getSelection && window.getSelection();
    var dir = decide({
      touches: 1,
      dx: t.clientX - start.x,
      dy: t.clientY - start.y,
      dt: Date.now() - start.time,
      startX: start.x,
      viewportWidth: window.innerWidth,
      path: location.pathname,
      blocked: start.blocked,
      selection: !!(sel && !sel.isCollapsed && String(sel).trim()),
    });
    start = null;
    if (!dir) return;
    try {
      window.webkit.messageHandlers.sift.postMessage({ type: 'swipe', dir: dir });
    } catch (err) {}
  }, { passive: true, capture: true });

  document.addEventListener('touchcancel', function () { start = null; }, { passive: true, capture: true });
})(typeof window !== 'undefined' ? window : globalThis);
