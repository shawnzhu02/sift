// Sift: YouTube filters that CSS can't express. Hides items by text and links,
// and keeps autoplay off.
(function () {
  if (window.__siftYouTube) return;
  window.__siftYouTube = true;

  var hide = window.__siftHide;

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

  function sweep() {
    // Any link to a Short: hide its tile (or its shelf).
    document.querySelectorAll('a[href^="/shorts/"]').forEach(function (a) {
      hide(a.closest(SHELF) || a.closest(TILE) || a);
    });

    // Bottom bar and chip/tab items named Home or Shorts.
    document.querySelectorAll('ytm-pivot-bar-item-renderer, yt-tab-shape, ytm-chip-cloud-chip-renderer')
      .forEach(function (el) {
        var label = (el.textContent || '').trim().toLowerCase();
        if (label === 'home' || label === 'shorts') hide(el);
      });

    // Shelves titled Shorts.
    document.querySelectorAll(SHELF).forEach(function (el) {
      var title = el.querySelector('h2, h3, .shelf-header-layout-wiz__title, .reel-shelf-title-wrapper');
      if (title && (title.textContent || '').trim().toLowerCase() === 'shorts') hide(el);
    });

    if (onWatchPage()) {
      // Everything after the video's own info and comments is recommendations.
      document.querySelectorAll(
        'ytm-single-column-watch-next-results-renderer ytm-item-section-renderer'
      ).forEach(function (section) {
        if (section.querySelector('ytm-video-with-context-renderer, ytm-compact-video-renderer, ytm-media-item, ytm-reel-shelf-renderer')) {
          hide(section);
        }
      });

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

  // Stop autoplay to the next video: when a video ends, stay on the page.
  document.addEventListener('ended', function (e) {
    if (e.target && e.target.tagName === 'VIDEO') {
      try { e.target.pause(); } catch (err) {}
    }
  }, true);

  window.__siftWatch(sweep);
})();
