import Foundation
import WebKit

/// Per-site web view setup: user agent and the injected filter scripts.
enum Site {
    /// Mobile Safari's user agent. Google sign-in refuses embedded web views
    /// (`disallowed_useragent`) unless the page thinks it is Safari.
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    static func title(_ site: SiteID) -> String {
        switch site {
        case .instagram: return "Messages"
        case .youtube: return "Subscriptions"
        }
    }

    static func symbol(_ site: SiteID) -> String {
        switch site {
        case .instagram: return "bubble.left.and.bubble.right"
        case .youtube: return "play.rectangle.on.rectangle"
        }
    }

    /// Scripts injected at document start in the main frame:
    /// the URL reporter, the site's CSS, then the site's hider script.
    static func userScripts(for site: SiteID) -> [WKUserScript] {
        var sources: [String] = []
        if let common = resource("common", "js") { sources.append(common) }
        if let css = resource(site.rawValue, "css") { sources.append(styleInjector(css)) }
        if let js = resource(site.rawValue, "js") { sources.append(js) }
        return sources.map {
            WKUserScript(source: $0, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        }
    }

    private static func resource(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Wraps CSS in a script that keeps a <style> tag in the page,
    /// re-adding it if the page rebuilds <head>.
    private static func styleInjector(_ css: String) -> String {
        let literal = (try? String(data: JSONEncoder().encode(css), encoding: .utf8)) ?? "\"\""
        return """
        (function () {
          var css = \(literal);
          function add() {
            if (document.getElementById('sift-css')) return;
            var root = document.head || document.documentElement;
            if (!root) return;
            var s = document.createElement('style');
            s.id = 'sift-css';
            s.textContent = css;
            root.appendChild(s);
          }
          add();
          document.addEventListener('DOMContentLoaded', add);
          new MutationObserver(add).observe(document, { childList: true, subtree: true });
        })();
        """
    }
}
