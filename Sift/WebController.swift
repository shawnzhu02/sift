import SwiftUI
import UIKit
import WebKit

/// The app's tabs, in tab-bar order. Feed and Clips show only when their
/// switches are on.
enum SiftTab: Int, CaseIterable, Identifiable {
    case messages
    case feed
    case clips
    case subscriptions
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .messages: return "Messages"
        case .feed: return "Feed"
        case .clips: return "Clips"
        case .subscriptions: return "Subscriptions"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .feed: return "square.grid.2x2.fill"
        case .clips: return "play.square.stack.fill"
        case .subscriptions: return "play.rectangle.on.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    static func visible(_ f: Features) -> [SiftTab] {
        allCases.filter { tab in
            switch tab {
            case .feed: return f.igFeed
            case .clips: return f.igReels != .off || f.ytShorts != .off
            default: return true
            }
        }
    }

    /// The tab a site's links open in.
    static func home(for site: SiteID) -> SiftTab {
        site == .instagram ? .messages : .subscriptions
    }
}

/// One web view's job. Each has its own web view; they share one cookie
/// store, so you sign in once per site.
enum WebRole: String, CaseIterable {
    case messages
    case feed
    case reels
    case subscriptions
    case shorts

    var site: SiteID {
        switch self {
        case .messages, .feed, .reels: return .instagram
        case .subscriptions, .shorts: return .youtube
        }
    }

    static func home(for site: SiteID) -> WebRole {
        site == .instagram ? .messages : .subscriptions
    }
}

/// Owns every web view (so they survive tab switches), the switches, the
/// following-only clip lists and the current tab.
@MainActor
final class WebStore: ObservableObject {
    @Published var tab: SiftTab = .messages
    /// Which site the Clips tab shows.
    @Published var clipSite: SiteID = .youtube
    /// A short note shown over the page (for example, the end of your clips).
    @Published var note: String?
    /// Set when new filters arrived this session; Settings re-reads its status.
    @Published var filtersUpdated = false

    let features: FeatureStore
    let clips: ClipAllowlist
    private(set) var controllers: [WebRole: WebController] = [:]
    private var hideNote: Task<Void, Never>?

    init() {
        let features = FeatureStore()
        self.features = features
        self.clips = ClipAllowlist()
        for role in WebRole.allCases {
            let controller = WebController(role: role, features: features.features)
            controller.store = self
            controllers[role] = controller
        }
        clipSite = Self.defaultClipSite(features.features)
        features.onChange = { [weak self] old, new in self?.featuresChanged(from: old, to: new) }
    }

    var visibleTabs: [SiftTab] { SiftTab.visible(features.features) }

    func controller(_ role: WebRole) -> WebController {
        controllers[role]!
    }

    func policy(for site: SiteID) -> RoutePolicy {
        RoutePolicy(features: features.features, clips: clips.list(site))
    }

    /// The web view the Clips tab shows now.
    var clipRole: WebRole { clipSite == .instagram ? .reels : .shorts }

    /// Where a role's page starts.
    func start(for role: WebRole) -> URL {
        switch role {
        case .messages: return Router.instagramInbox
        case .feed: return Router.instagramFollowing
        case .subscriptions: return Router.youtubeSubscriptions
        case .reels:
            if features.features.igReels == .following {
                if let first = clips.list(.instagram).ids.first { return Router.reelURL(first) }
                return Router.instagramFollowing
            }
            return URL(string: "https://www.instagram.com/reels/")!
        case .shorts:
            if features.features.ytShorts == .following {
                if let first = clips.list(.youtube).ids.first { return Router.shortURL(first) }
                return Router.youtubeSubscriptions
            }
            return URL(string: "https://m.youtube.com/shorts")!
        }
    }

    /// Moves one tab left (-1) or right (+1) among the visible tabs. No wrap-around.
    func step(_ delta: Int) {
        let tabs = visibleTabs
        guard let i = tabs.firstIndex(of: tab) else { tab = .messages; return }
        let next = i + delta
        guard tabs.indices.contains(next) else { return }
        tab = tabs[next]
    }

    /// Tapping the current tab again takes its page back to the start.
    func select(_ target: SiftTab) {
        if target == tab {
            switch target {
            case .messages: controller(.messages).goHome()
            case .feed: controller(.feed).goHome()
            case .clips: controller(clipRole).goHome()
            case .subscriptions: controller(.subscriptions).goHome()
            case .settings: break
            }
        }
        tab = target
    }

    /// Opens a link that came from another page.
    func openShared(_ url: URL, in site: SiteID) {
        tab = .home(for: site)
        controller(.home(for: site)).loadShared(url)
    }

    func open(_ url: URL, in site: SiteID) {
        tab = .home(for: site)
        controller(.home(for: site)).load(url)
    }

    /// Opens the site's login page on its own page.
    func connect(_ site: SiteID) {
        open(Router.loginURL(for: site), in: site)
    }

    func show(note text: String) {
        note = text
        hideNote?.cancel()
        hideNote = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            note = nil
        }
    }

    /// Clears cookies and site data for every page (signs out of everything).
    func signOutEverywhere() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                self.controllers.values.forEach { $0.reset() }
            }
        }
    }

    private static func defaultClipSite(_ f: Features) -> SiteID {
        f.ytShorts == .off && f.igReels != .off ? .instagram : .youtube
    }

    /// Looks for new filters (see FilterUpdates). New ones apply from the
    /// next page load, so nothing reloads under the user.
    func checkFilterUpdates(force: Bool = false) async {
        guard await FilterUpdates.refresh(force: force) else { return }
        controllers.values.forEach { $0.loadScripts(features.features) }
        filtersUpdated = true
    }

    private func featuresChanged(from old: Features, to new: Features) {
        // Rebuild every page's scripts, but reload only the pages whose flags
        // changed (flipping a YouTube switch must not reload an open DM).
        for (role, controller) in controllers {
            if Site.flags(for: role, features: old) == Site.flags(for: role, features: new) {
                controller.loadScripts(new)
            } else {
                controller.apply(features: new)
            }
        }
        if !visibleTabs.contains(tab) { tab = .settings }
        if new.clips(clipSite) == .off { clipSite = Self.defaultClipSite(new) }
    }
}

/// One filtered web view. Every main-frame load and every in-page URL change
/// goes through `Router.decide`.
@MainActor
final class WebController: NSObject, ObservableObject {
    let role: WebRole
    var site: SiteID { role.site }
    let webView: WKWebView
    weak var store: WebStore?

    /// The page's background color, for the status bar and home indicator strips.
    @Published private(set) var pageColor = Color(.systemBackground)

    /// Last URL the router allowed in this tab.
    private var lastAllowed: URL?
    /// The next navigation came from a link shared in the other tab.
    private var sharedPending = false

    init(role: WebRole, features: Features) {
        self.role = role

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
        Site.userScripts(for: role, features: features).forEach(content.addUserScript)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func loadStartIfNeeded() {
        guard webView.url == nil else { return }
        #if DEBUG
        if role == .messages, TestPage.isActive {
            webView.loadHTMLString(TestPage.html, baseURL: Router.instagramInbox)
            return
        }
        #endif
        goHome()
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func loadShared(_ url: URL) {
        sharedPending = true
        load(url)
    }

    func goHome() {
        load(store?.start(for: role) ?? Router.start(for: site))
    }

    /// New switches: swap the page scripts and reload an open page.
    func apply(features: Features) {
        loadScripts(features)
        guard webView.url != nil else { return }
        lastAllowed = nil
        goHome()
    }

    /// Swaps in fresh scripts without reloading; they apply on the next page load.
    func loadScripts(_ features: Features) {
        let content = webView.configuration.userContentController
        content.removeAllUserScripts()
        Site.userScripts(for: role, features: features).forEach(content.addUserScript)
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

    private var policy: RoutePolicy {
        store?.policy(for: site) ?? RoutePolicy()
    }

    /// Decides a URL, and says so when a following-only swipe hits the end.
    private func decide(_ url: URL) -> RouteDecision {
        let decision = Router.decide(url, in: site, context: context, policy: policy)
        if case .redirect(let target) = decision, target == lastAllowed,
           policy.features.clips(site) == .following,
           let id = Router.clipID(url), let last = lastAllowed, Router.clipID(last) != nil, Router.clipID(last) != id {
            store?.show(note: site == .instagram
                ? "That's all from people you follow"
                : "That's all from your subscriptions")
        }
        return decision
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

    /// Background color reported by common.js.
    fileprivate func colorReported(_ value: String) {
        if let color = CSSColor.color(value) { pageColor = color }
    }

    /// Swipe reported by swipe.js.
    fileprivate func swipeReported(_ dir: String) {
        store?.step(dir == "next" ? 1 : -1)
    }

    /// Clip ids from a following-only page, reported by the site script.
    fileprivate func clipsReported(_ ids: [String]) {
        store?.clips.add(ids, for: site)
    }

    /// In-page URL change reported by common.js.
    fileprivate func pageReported(_ url: URL) {
        guard url != lastAllowed else { return }
        let decision = decide(url)
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
        let decision = decide(url)
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
            let decision = decide(url)
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
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "color":
            guard let value = body["value"] as? String else { return }
            Task { @MainActor in self.target?.colorReported(value) }
        case "swipe":
            guard let dir = body["dir"] as? String else { return }
            Task { @MainActor in self.target?.swipeReported(dir) }
        case "clips":
            guard let ids = body["ids"] as? [String] else { return }
            let clean = ids.filter { id in id.count <= 64 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } }
            Task { @MainActor in self.target?.clipsReported(clean) }
        default:
            guard let href = body["href"] as? String, let url = URL(string: href) else { return }
            Task { @MainActor in self.target?.pageReported(url) }
        }
    }
}

/// SwiftUI wrapper. The web view itself lives in WebController.
struct WebTab: UIViewRepresentable {
    let controller: WebController

    func makeUIView(context: Context) -> WKWebView {
        controller.loadStartIfNeeded()
        let webView = controller.webView
        // The web view sits inside the safe area with no content insets. Insets made
        // taps on Instagram's fixed layouts land one row below the finger. The
        // strips above and below are painted natively in the page's color.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.underPageBackgroundColor = nil  // nil = use the page's own background color
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
