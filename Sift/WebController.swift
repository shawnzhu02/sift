import SwiftUI
import UIKit
import WebKit

enum AppTab: Hashable {
    case site(SiteID)
    case settings
}

/// Owns both web views (so they survive tab switches) and the selected tab.
@MainActor
final class WebStore: ObservableObject {
    @Published var selected: AppTab = .site(.instagram)

    let instagram: WebController
    let youtube: WebController

    init() {
        instagram = WebController(site: .instagram)
        youtube = WebController(site: .youtube)
        instagram.store = self
        youtube.store = self
    }

    func controller(_ site: SiteID) -> WebController {
        site == .instagram ? instagram : youtube
    }

    /// Opens a link that came from the other tab.
    func openShared(_ url: URL, in site: SiteID) {
        selected = .site(site)
        controller(site).loadShared(url)
    }

    func open(_ url: URL, in site: SiteID) {
        selected = .site(site)
        controller(site).load(url)
    }

    /// Clears cookies and site data for both tabs (signs out of everything).
    func signOutEverywhere() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                self.instagram.reset()
                self.youtube.reset()
            }
        }
    }
}

/// One filtered web view. Every main-frame load and every in-page URL change
/// goes through `Router.decide`.
@MainActor
final class WebController: NSObject, ObservableObject {
    let site: SiteID
    let webView: WKWebView
    weak var store: WebStore?

    /// Last URL the router allowed in this tab.
    private var lastAllowed: URL?
    /// The next navigation came from a link shared in the other tab.
    private var sharedPending = false

    init(site: SiteID) {
        self.site = site

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        let content = WKUserContentController()
        config.userContentController = content

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.customUserAgent = Site.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        content.add(WeakScriptHandler(self), name: "sift")
        Site.userScripts(for: site).forEach(content.addUserScript)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func loadStartIfNeeded() {
        if webView.url == nil { load(Router.start(for: site)) }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func loadShared(_ url: URL) {
        sharedPending = true
        load(url)
    }

    func goHome() {
        load(Router.start(for: site))
    }

    func reset() {
        lastAllowed = nil
        sharedPending = false
        goHome()
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }

    private var context: RouteContext {
        RouteContext(previous: lastAllowed, fromSharedLink: sharedPending)
    }

    /// Acts on a non-allow decision.
    /// `inPage` is true when the page already changed its URL with the History API,
    /// so a redirect must replace the current history entry.
    /// `userTap` is true only for link taps. Leaving the tab (other tab or Safari)
    /// needs one, so a page can't push you out on its own.
    private func apply(_ decision: RouteDecision, inPage: Bool, userTap: Bool = false) {
        switch decision {
        case .allow, .block:
            break
        case .switchTab, .openExternal:
            guard userTap, !inPage else { return }
            leave(decision)
        case .redirect(let target):
            if inPage, let literal = jsString(target.absoluteString) {
                webView.evaluateJavaScript("location.replace(\(literal));", completionHandler: nil)
            } else {
                load(target)
            }
        }
    }

    private func leave(_ decision: RouteDecision) {
        switch decision {
        case .switchTab(let other, let target):
            store?.openShared(target, in: other)
        case .openExternal(let target):
            UIApplication.shared.open(target)
        default:
            break
        }
    }

    private func allow(_ url: URL) {
        lastAllowed = url
        sharedPending = false
    }

    private func jsString(_ s: String) -> String? {
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// In-page URL change reported by common.js.
    fileprivate func pageReported(_ url: URL) {
        guard url != lastAllowed else { return }
        let decision = Router.decide(url, in: site, context: context)
        if decision == .allow {
            allow(url)
        } else {
            apply(decision, inPage: true)
        }
    }
}

extension WebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        // Only route top-level pages. Iframes (players, login widgets) load freely.
        if let frame = action.targetFrame, !frame.isMainFrame {
            return .allow
        }
        let decision = Router.decide(url, in: site, context: context)
        if decision == .allow {
            allow(url)
            return .allow
        }
        // Act after WebKit has cancelled this navigation.
        let userTap = action.navigationType == .linkActivated
        DispatchQueue.main.async { self.apply(decision, inPage: false, userTap: userTap) }
        return .cancel
    }
}

extension WebController: WKUIDelegate {
    /// `target=_blank` links: open them in this same view, through the router.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url {
            let decision = Router.decide(url, in: site, context: context)
            if decision == .allow {
                load(url)
            } else {
                apply(decision, inPage: false, userTap: action.navigationType == .linkActivated)
            }
        }
        return nil
    }
}

/// Breaks the retain cycle between WKUserContentController and its handler.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebController?

    init(_ target: WebController) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let href = body["href"] as? String,
              let url = URL(string: href)
        else { return }
        Task { @MainActor in self.target?.pageReported(url) }
    }
}

/// SwiftUI wrapper. The web view itself lives in WebController.
struct WebTab: UIViewRepresentable {
    let controller: WebController

    func makeUIView(context: Context) -> WKWebView {
        controller.loadStartIfNeeded()
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
