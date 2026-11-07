#if DEBUG
import Foundation

/// UI-test stand-in for Instagram's DM inbox (fixed shell, inner scrolling list).
/// Loaded only when the launch environment has SIFT_TEST_PAGE=1.
enum TestPage {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["SIFT_TEST_PAGE"] != nil
    }

    /// "1": fixed shell with an inner scrolling list.
    /// "2": the document scrolls under a fixed header and a fixed bottom bar.
    static var html: String {
        ProcessInfo.processInfo.environment["SIFT_TEST_PAGE"] == "2" ? documentScroll : fixedShell
    }

    static let documentScroll = """
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { margin: 0; padding: 60px 0 50px; font: 17px -apple-system, sans-serif; }
      #header { position: fixed; top: 0; left: 0; right: 0; height: 60px; display: flex; align-items: center; padding-left: 16px; background: #eee; z-index: 2; }
      #nav { position: fixed; bottom: 0; left: 0; right: 0; height: 50px; background: #ccc; z-index: 2; }
      .row { height: 64px; display: flex; align-items: center; padding-left: 16px; color: #fff; }
    </style></head>
    <body><div id="header"><span id="status">none</span></div><div id="list"></div><div id="nav"></div>
    <script>
      var list = document.getElementById('list');
      for (var i = 1; i <= 30; i++) {
        var d = document.createElement('div');
        d.className = 'row';
        d.textContent = 'Row ' + i;
        d.style.background = 'rgb(' + (i * 8) + ', 120, 60)';
        d.onclick = (function (n) { return function () { document.getElementById('status').textContent = 'clicked ' + n; }; })(i);
        list.appendChild(d);
      }
    </script></body></html>
    """

    static let fixedShell = """
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      html, body { margin: 0; height: 100%; overflow: hidden; font: 17px -apple-system, sans-serif; }
      #shell { position: fixed; inset: 0; display: flex; flex-direction: column; }
      #header { height: 60px; flex: none; display: flex; align-items: center; padding-left: 16px; background: #eee; }
      #list { height: calc(100vh - 60px); overflow-y: auto; }
      .row { height: 64px; display: flex; align-items: center; padding-left: 16px; color: #fff; }
    </style></head>
    <body><div id="shell"><div id="header"><span id="status">none</span></div><div id="list"></div></div>
    <script>
      var list = document.getElementById('list');
      for (var i = 1; i <= 30; i++) {
        var d = document.createElement('div');
        d.className = 'row';
        d.textContent = 'Row ' + i;
        d.style.background = 'rgb(' + (i * 8) + ', 120, 60)';
        d.onclick = (function (n) { return function () { document.getElementById('status').textContent = 'clicked ' + n; }; })(i);
        list.appendChild(d);
      }
    </script></body></html>
    """
}
#endif
