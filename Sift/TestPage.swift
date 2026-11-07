#if DEBUG
import Foundation

/// UI-test stand-in for Instagram's DM inbox (fixed shell, inner scrolling list).
/// Loaded only when the launch environment has SIFT_TEST_PAGE=1.
enum TestPage {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["SIFT_TEST_PAGE"] == "1"
    }

    static let html = """
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      html, body { margin: 0; height: 100%; overflow: hidden; font: 17px -apple-system, sans-serif; }
      #shell { position: fixed; inset: 0; display: flex; flex-direction: column; }
      #header { height: 60px; flex: none; display: flex; align-items: center; padding-left: 16px; background: #eee; }
      #list { height: calc(100vh - 60px); overflow-y: auto; }
      .row { height: 64px; display: flex; align-items: center; padding-left: 16px; border-bottom: 1px solid #ddd; }
    </style></head>
    <body><div id="shell"><div id="header"><span id="status">none</span></div><div id="list"></div></div>
    <script>
      var list = document.getElementById('list');
      for (var i = 1; i <= 30; i++) {
        var d = document.createElement('div');
        d.className = 'row';
        d.textContent = 'Row ' + i;
        d.onclick = (function (n) { return function () { document.getElementById('status').textContent = 'clicked ' + n; }; })(i);
        list.appendChild(d);
      }
    </script></body></html>
    """
}
#endif
