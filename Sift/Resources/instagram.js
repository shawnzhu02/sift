// Sift: Instagram filters that CSS can't express (text-matched sections), and
// (in following-only Reels mode) collecting reels from people you follow.
// Each part follows its Settings switch via window.__siftHas('no-...').
(function () {
  if (window.__siftInstagram) return;
  window.__siftInstagram = true;

  var hide = window.__siftHide;
  var has = window.__siftHas || function () { return false; };

  // Reel ids linked on the page, in page order.
  function reelIds() {
    var ids = [];
    document.querySelectorAll('a[href*="/reel/"], a[href*="/reels/"]').forEach(function (a) {
      var m = /\/reels?\/([A-Za-z0-9_-]+)\/?/.exec(a.getAttribute('href') || '');
      if (m && m[1] !== 'audio' && ids.indexOf(m[1]) === -1) ids.push(m[1]);
    });
    return ids;
  }

  // A profile you follow: its header button reads "Following".
  function followedProfile() {
    var buttons = document.querySelectorAll('header button, header [role="button"]');
    for (var i = 0; i < buttons.length; i++) {
      if ((buttons[i].textContent || '').trim().toLowerCase() === 'following') return true;
    }
    return false;
  }

  var lastSent = '';
  function collectClips() {
    if (!has('clips-following')) return;
    var parts = location.pathname.split('/').filter(Boolean);
    var followingFeed = parts.length === 0 && /[?&]variant=following/.test(location.search);
    if (!followingFeed && !(parts.length >= 1 && parts.length <= 2 && followedProfile())) return;
    var ids = reelIds();
    var key = ids.join(',');
    if (!ids.length || key === lastSent) return;
    lastSent = key;
    try {
      window.webkit.messageHandlers.sift.postMessage({ type: 'clips', ids: ids });
    } catch (e) {}
  }

  // Section headings whose whole block is recommended content.
  var BLOCKED_HEADINGS = ['suggested for you', 'suggested posts', 'more posts from', 'more reels'];

  function headingBlocked(text) {
    var t = (text || '').trim().toLowerCase();
    return BLOCKED_HEADINGS.some(function (h) { return t.indexOf(h) === 0; });
  }

  // Pages made of many sections (notifications, activity) put the heading next
  // to the whole list. Walking up there hid the entire page (a grey screen),
  // so only the heading itself goes on those pages.
  function listPage() {
    var p = location.pathname;
    return p.indexOf('/notifications') === 0 || p.indexOf('/accounts/activity') === 0;
  }

  // A block as tall as the screen is the page, never a recommendation block.
  function pageSized(node) {
    var r = node.getBoundingClientRect();
    return r.height >= window.innerHeight * 0.8 && r.width >= window.innerWidth * 0.9;
  }

  // Walk up to the nearest ancestor that also holds content besides the heading.
  function sectionFor(el) {
    if (listPage()) return el;
    var node = el;
    for (var i = 0; i < 6 && node.parentElement; i++) {
      node = node.parentElement;
      if (pageSized(node)) return el;
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

  // Instagram's bottom bar (Home, Explore, Reels, Create, Profile). Sift has
  // its own tab bar, so the whole bar goes, except on the Feed page while
  // posting is on (Create lives there). Never the DM composer.
  var NAV_LINKS = 'a[href="/"], a[href="/explore/"], a[href="/reels/"], a[href="/direct/inbox/"]';

  function hideBottomNav() {
    var vh = window.innerHeight;
    document.querySelectorAll(NAV_LINKS).forEach(function (a) {
      for (var node = a.parentElement; node && node !== document.body; node = node.parentElement) {
        var style = getComputedStyle(node);
        if (style.position !== 'fixed' && style.position !== 'sticky') continue;
        var rect = node.getBoundingClientRect();
        var atBottom = rect.bottom >= vh - 2 && rect.height < vh * 0.25;
        if (atBottom && !node.querySelector('textarea, [contenteditable="true"], [role="textbox"]')) {
          hide(node);
        }
        break;
      }
    });
  }

  // The Following feed ends. Posts after the first one you have already seen,
  // older than 3 days, or past the per-visit cap are hidden, and a card says
  // you're caught up. A post counts as seen once half of it was on screen.
  var SEEN_KEY = 'sift.seen';
  var seen = {};
  var seenBefore = null; // the list as it was when this page loaded
  var observer = null;

  function loadSeen() {
    try { seen = JSON.parse(localStorage.getItem(SEEN_KEY) || '{}') || {}; } catch (e) { seen = {}; }
    var cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    Object.keys(seen).forEach(function (k) { if (seen[k] < cutoff) delete seen[k]; });
    seenBefore = {};
    Object.keys(seen).forEach(function (k) { seenBefore[k] = seen[k]; });
  }

  function saveSeen() {
    try { localStorage.setItem(SEEN_KEY, JSON.stringify(seen)); } catch (e) {}
  }

  function postId(article) {
    var a = article.querySelector('a[href*="/p/"], a[href*="/reel/"]');
    var m = a && /\/(?:p|reel)\/([A-Za-z0-9_-]+)/.exec(a.getAttribute('href') || '');
    return m ? m[1] : null;
  }

  function postAge(article) {
    var t = article.querySelector('time[datetime]');
    var ms = t ? Date.parse(t.getAttribute('datetime')) : NaN;
    return isNaN(ms) ? null : Date.now() - ms;
  }

  function markSeen(entries) {
    var changed = false;
    entries.forEach(function (e) {
      if (!e.isIntersecting || e.intersectionRatio < 0.5) return;
      var id = postId(e.target);
      if (id && !seen[id]) { seen[id] = Date.now(); changed = true; }
    });
    if (changed) saveSeen();
  }

  function endCard() {
    var card = document.getElementById('sift-caughtup');
    if (card) return card;
    card = document.createElement('div');
    card.id = 'sift-caughtup';
    card.innerHTML = '<strong>You’re all caught up</strong><span>New posts from people you follow show up here. Pull down to check again.</span>';
    return card;
  }

  function limitFeed() {
    if (window.__siftRole !== 'feed') return;
    if (location.pathname !== '/' || !/[?&]variant=following/.test(location.search)) return;
    var caughtUp = has('feed-caughtup');
    var max = window.__siftValue ? window.__siftValue('feed-max-') : 0;
    if (!caughtUp && !max) return;
    if (seenBefore === null) loadSeen();
    if (!observer && 'IntersectionObserver' in window) observer = new IntersectionObserver(markSeen, { threshold: [0.5] });

    var articles = Array.prototype.slice.call(document.querySelectorAll('article'));
    var stop = -1;
    for (var i = 0; i < articles.length; i++) {
      var a = articles[i];
      if (observer && !a.__siftWatched) { a.__siftWatched = true; observer.observe(a); }
      if (stop !== -1) continue;
      var id = postId(a);
      var age = postAge(a);
      if (max && i >= max) stop = i;
      else if (caughtUp && ((id && seenBefore[id]) || (age !== null && age > 3 * 24 * 3600 * 1000))) stop = i;
    }
    // Never hide the very first post: the feed always shows something.
    if (stop === 0) stop = 1;
    if (stop === -1 || stop >= articles.length) return;
    for (var j = stop; j < articles.length; j++) hide(articles[j]);
    var card = endCard();
    var first = articles[stop];
    if (first.parentElement && card.parentElement !== first.parentElement) first.parentElement.insertBefore(card, first);
  }

  function sweep() {
    if (!has('keep-nav')) hideBottomNav();
    collectClips();
    limitFeed();

    // DMs change constantly (typing, timestamps, new messages) and hold no
    // recommendations, so skip the heavier scans there.
    if (location.pathname.indexOf('/direct/') === 0) return;

    // Profile Reels tab (also matched in CSS when it has role=tab).
    if (has('no-reels')) {
      document.querySelectorAll('a[href$="/reels/"]').forEach(function (a) {
        var parts = a.getAttribute('href').split('/').filter(Boolean);
        if (parts.length === 2 && parts[1] === 'reels') hide(a);
      });
    }

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
