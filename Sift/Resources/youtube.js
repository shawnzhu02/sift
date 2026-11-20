// Sift: YouTube filters that CSS can't express. Hides items by text and links,
// keeps autoplay off, and (in following-only Shorts mode) collects the Shorts
// your subscriptions posted. Each part follows its Settings switch via
// window.__siftHas('no-...').
(function () {
  if (window.__siftYouTube) return;
  window.__siftYouTube = true;

  var hide = window.__siftHide;
  var has = window.__siftHas || function () { return false; };

  // Containers for one video tile, in the order to try.
  var TILE = [
    'ytm-rich-item-renderer',
    'ytm-video-with-context-renderer',
    'ytm-compact-video-renderer',
    'ytm-media-item',
    'ytm-shorts-lockup-view-model',
    'ytm-shorts-lockup-view-model-v2',
    'ytm-reel-item-renderer',
  ].join(',');

  // Whole sections that hold Shorts.
  var SHELF = [
    'ytm-reel-shelf-renderer',
    'ytm-rich-section-renderer',
    'grid-shelf-view-model',
  ].join(',');

  function onWatchPage() {
    return location.pathname === '/watch';
  }

  // Short ids linked on the page, in page order.
  function shortIds() {
    var ids = [];
    document.querySelectorAll('a[href^="/shorts/"]').forEach(function (a) {
      var m = /^\/shorts\/([A-Za-z0-9_-]+)/.exec(a.getAttribute('href') || '');
      if (m && ids.indexOf(m[1]) === -1) ids.push(m[1]);
    });
    return ids;
  }

  // A channel page whose Subscribe button says you're subscribed.
  function subscribedChannel() {
    var btn = document.querySelector(
      'ytm-subscribe-button-renderer button, yt-subscribe-button-view-model button, .c4-tabbed-header-subscribe button'
    );
    if (!btn) return false;
    var label = ((btn.getAttribute('aria-label') || '') + ' ' + (btn.textContent || '')).toLowerCase();
    return label.indexOf('unsubscribe') !== -1 || label.indexOf('subscribed') !== -1;
  }

  var lastSent = '';
  function collectClips() {
    if (!has('clips-following')) return;
    var path = location.pathname;
    var followedPage =
      path.indexOf('/feed/subscriptions') === 0 ||
      (/\/shorts\/?$/.test(path) && path.indexOf('/shorts') !== 0 && subscribedChannel());
    if (!followedPage) return;
    var ids = shortIds();
    var key = ids.join(',');
    if (!ids.length || key === lastSent) return;
    lastSent = key;
    try {
      window.webkit.messageHandlers.sift.postMessage({ type: 'clips', ids: ids });
    } catch (e) {}
  }

  function sweep() {
    collectClips();

    if (has('no-shorts')) {
      // Any link to a Short: hide its tile (or its shelf).
      document.querySelectorAll('a[href^="/shorts/"]').forEach(function (a) {
        hide(a.closest(SHELF) || a.closest(TILE) || a);
      });
      // Shelves titled Shorts.
      document.querySelectorAll(SHELF).forEach(function (el) {
        var title = el.querySelector('h2, h3, .shelf-header-layout-wiz__title, .reel-shelf-title-wrapper');
        if (title && (title.textContent || '').trim().toLowerCase() === 'shorts') hide(el);
      });
    }

    // Bottom bar and chip/tab items named Home or Shorts.
    document.querySelectorAll('ytm-pivot-bar-item-renderer, yt-tab-shape, ytm-chip-cloud-chip-renderer')
      .forEach(function (el) {
        var label = (el.textContent || '').trim().toLowerCase();
        if ((label === 'home' && has('no-home')) || (label === 'shorts' && has('no-shorts'))) hide(el);
      });

    // "Watch in YouTube app" pop-up: close it (or hide it if there's no close button).
    document.querySelectorAll('dialog, .dialog-container, ytm-mealbar-promo-renderer').forEach(function (d) {
      var text = (d.textContent || '').toLowerCase();
      if (text.indexOf('youtube app') === -1 && text.indexOf('open app') === -1) return;
      var close = d.querySelector('button[aria-label="Close"], [aria-label="Close"] button, button[aria-label*="lose"]');
      if (close && !close.__siftClicked) {
        close.__siftClicked = true;
        close.click();
      } else {
        hide(d.closest('.dialog-container') || d);
      }
    });

    if (onWatchPage()) {
      if (has('no-upnext')) {
        // Everything after the video's own info and comments is recommendations.
        document.querySelectorAll(
          'ytm-single-column-watch-next-results-renderer ytm-item-section-renderer'
        ).forEach(function (section) {
          if (section.querySelector('ytm-comment-section-renderer, ytm-comments-entry-point-header-renderer')) return;
          if (section.querySelector('ytm-video-with-context-renderer, ytm-compact-video-renderer, ytm-media-item, ytm-reel-shelf-renderer')) {
            hide(section);
          }
        });
      }

      if (has('no-autoplay')) {
        // Autoplay toggle: switch it off once per page.
        var toggle = document.querySelector(
          '.ytm-autonav-toggle-button-container button[aria-pressed="true"], ' +
          '.ytp-autonav-toggle-button[aria-checked="true"]'
        );
        if (toggle && !toggle.__siftOff) {
          toggle.__siftOff = true;
          toggle.click();
        }
      }
    }
  }

  // Autoplay off: when a video ends, stay on the page.
  document.addEventListener('ended', function (e) {
    if (!has('no-autoplay')) return;
    if (e.target && e.target.tagName === 'VIDEO' && onWatchPage()) {
      try { e.target.pause(); } catch (err) {}
    }
  }, true);

  window.__siftWatch(sweep);
})();
