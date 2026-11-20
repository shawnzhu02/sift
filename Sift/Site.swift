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

    /// Scripts injected at document start in the main frame: the switches,
    /// the URL reporter, the swipe detector, the site's CSS, then the site's hider script.
    static func userScripts(for role: WebRole, features: Features) -> [WKUserScript] {
        let site = role.site
        var flags = features.flags(for: site)
        // Posting lives in Instagram's own bottom bar, so the Feed page keeps it.
        if role == .feed, features.igPosting { flags.append("keep-nav") }
        var sources: [String] = [flagScript(flags, role: role)]
        if let common = resource("common", "js") { sources.append(common) }
        if let swipe = resource("swipe", "js") { sources.append(swipe) }
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

    /// Puts the switches on the page as `<html data-sift="no-shorts ...">` (for
    /// the CSS) and `window.__siftHas(flag)` (for the scripts), and keeps the
    /// attribute there if the page rewrites it.
    private static func flagScript(_ flags: [String], role: WebRole) -> String {
        let list = flags.joined(separator: " ")
        let literal = (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "\"\""
        let roleLiteral = (try? String(data: JSONEncoder().encode(role.rawValue), encoding: .utf8)) ?? "\"\""
        return """
        (function () {
          var flags = \(literal);
          var words = flags ? flags.split(' ') : [];
          window.__siftRole = \(roleLiteral);
          window.__siftHas = function (flag) { return words.indexOf(flag) !== -1; };
          function set() {
            var html = document.documentElement;
            if (html && html.getAttribute('data-sift') !== flags) html.setAttribute('data-sift', flags);
          }
          set();
          document.addEventListener('DOMContentLoaded', set);
          if (document.documentElement) {
            new MutationObserver(set).observe(document.documentElement, { attributes: true, attributeFilter: ['data-sift'] });
          }
        })();
        """
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
          document.addEventListener('DOMContentLoaded', function () {
            add();
            // Re-add only if the page rebuilds <head>; no whole-page watching.
            if (document.head) new MutationObserver(add).observe(document.head, { childList: true });
          });
          new MutationObserver(add).observe(document, { childList: true });
          if (document.documentElement) new MutationObserver(add).observe(document.documentElement, { childList: true });
        })();
        """
    }
}
