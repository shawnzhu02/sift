import Foundation

/// The two filtered sites. Each gets its own tab and web view.
enum SiteID: String, CaseIterable, Identifiable {
    case instagram
    case youtube

    var id: String { rawValue }
}

/// What the web view should do with a URL.
enum RouteDecision: Equatable {
    /// Load it.
    case allow
    /// Load this URL instead (replaces the history entry for in-page changes).
    case redirect(URL)
    /// The URL belongs to the other site: open it in that tab.
    case switchTab(SiteID, URL)
    /// Not Instagram or YouTube: hand it to Safari.
    case openExternal(URL)
    /// Drop it (for example `instagram://` links that would open the native app).
    case block
}

/// What the tab saw before this URL.
struct RouteContext: Equatable {
    /// The last URL this tab allowed. `nil` before the first page load.
    var previous: URL?
    /// True when the URL arrived from outside the tab (a link shared in the other tab).
    var fromSharedLink: Bool

    init(previous: URL? = nil, fromSharedLink: Bool = false) {
        self.previous = previous
        self.fromSharedLink = fromSharedLink
    }
}

/// All URL policy lives here, so it can be unit-tested without a web view.
///
/// Instagram: DMs, profiles, single posts, search and settings only.
/// Reels and stories open only from DMs, and never chain into the next one.
///
/// YouTube: Subscriptions, search, channels, watch pages and settings.
/// Home, Shorts and trending feeds go to Subscriptions.
enum Router {
    static let instagramInbox = URL(string: "https://www.instagram.com/direct/inbox/")!
    static let youtubeSubscriptions = URL(string: "https://m.youtube.com/feed/subscriptions")!

    static func start(for site: SiteID) -> URL {
        switch site {
        case .instagram: return instagramInbox
        case .youtube: return youtubeSubscriptions
        }
    }

    // MARK: - Entry point

    static func decide(_ url: URL, in tab: SiteID, context: RouteContext = RouteContext()) -> RouteDecision {
        guard let scheme = url.scheme?.lowercased() else { return .allow }

        if scheme != "http" && scheme != "https" {
            switch scheme {
            case "about", "blob", "data", "javascript":
                return .allow
            case "instagram", "youtube", "vnd.youtube", "itms-apps", "itms-appss":
                return .block
            default:
                return .openExternal(url)
            }
        }

        guard let host = url.host?.lowercased() else { return .allow }

        if let target = unwrapRedirect(url) {
            return crossing(to: target, from: tab)
        }

        guard let site = site(forHost: host) else {
            return isAuthHost(host, for: tab) ? .allow : .openExternal(url)
        }
        if site != tab {
            return .switchTab(site, url)
        }

        switch tab {
        case .instagram: return instagram(url, context)
        case .youtube: return youtube(url, context)
        }
    }

    // MARK: - Hosts

    static func site(forHost host: String) -> SiteID? {
        let h = host.lowercased()
        if h == "instagram.com" || h.hasSuffix(".instagram.com") || h == "instagr.am" {
            return .instagram
        }
        if h == "youtube.com" || h.hasSuffix(".youtube.com") || h == "youtu.be" {
            return .youtube
        }
        return nil
    }

    /// Login and account hosts each site needs inside its own tab.
    static func isAuthHost(_ host: String, for tab: SiteID) -> Bool {
        let h = host.lowercased()
        func under(_ domain: String) -> Bool { h == domain || h.hasSuffix("." + domain) }
        switch tab {
        case .instagram:
            return under("facebook.com") || under("meta.com") || under("fb.com")
        case .youtube:
            return under("google.com")
        }
    }

    /// Link-wrapping redirectors: returns the real destination.
    static func unwrapRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path

        if host == "l.instagram.com" {
            return queryURL(url, "u")
        }
        if site(forHost: host) == .youtube, path == "/redirect" {
            return queryURL(url, "q")
        }
        if (host == "www.google.com" || host == "google.com"), path == "/url" {
            return queryURL(url, "q") ?? queryURL(url, "url")
        }
        return nil
    }

    private static func crossing(to target: URL, from tab: SiteID) -> RouteDecision {
        guard let host = target.host?.lowercased(), let site = site(forHost: host) else {
            return .openExternal(target)
        }
        return site == tab ? .redirect(target) : .switchTab(site, target)
    }

    // MARK: - Instagram

    /// First path segments that are not usernames.
    static let instagramReserved: Set<String> = [
        "direct", "accounts", "p", "reel", "reels", "tv", "stories", "explore",
        "about", "legal", "challenge", "emails", "web", "api", "oauth", "privacy",
        "session", "your_activity", "notifications", "settings", "account_center", "ar",
    ]

    static func instagram(_ url: URL, _ ctx: RouteContext) -> RouteDecision {
        let seg = segments(url)
        guard let first = seg.first?.lowercased() else {
            return .redirect(instagramInbox)  // home feed
        }

        switch first {
        case "explore":
            // Search for people is fine. The explore grid is not.
            if seg.count >= 2, seg[1].lowercased() == "search" { return .allow }
            return .redirect(instagramInbox)

        case "reels":
            // `/reels/` is the endless feed. `/reels/<id>/` is one reel.
            // `/reels/audio/<id>/` lists reels for a sound.
            guard seg.count >= 2, seg[1].lowercased() != "audio" else {
                return .redirect(instagramInbox)
            }
            return singleReel(id: seg[1], ctx)

        case "reel", "tv":
            guard seg.count >= 2 else { return .redirect(instagramInbox) }
            return singleReel(id: seg[1], ctx)

        case "stories":
            return stories(seg, ctx)

        default:
            guard !instagramReserved.contains(first), seg.count >= 2 else { return .allow }
            let second = seg[1].lowercased()
            // Newer username-prefixed links: /<user>/reel/<id>/
            if (second == "reel" || second == "reels"), seg.count >= 3 {
                return singleReel(id: seg[2], ctx)
            }
            // A profile's Reels tab: back to the profile grid.
            if second == "reels" {
                return .redirect(URL(string: "https://www.instagram.com/\(seg[0])/")!)
            }
            return .allow
        }
    }

    /// The reel id in an Instagram path, if it is a reel page.
    static func reelID(_ seg: [String]) -> String? {
        guard let first = seg.first?.lowercased() else { return nil }
        if ["reel", "reels", "tv"].contains(first) {
            return seg.count >= 2 && seg[1].lowercased() != "audio" ? seg[1] : nil
        }
        if !instagramReserved.contains(first), seg.count >= 3,
           ["reel", "reels"].contains(seg[1].lowercased()) {
            return seg[2]
        }
        return nil
    }

    private static func singleReel(id: String, _ ctx: RouteContext) -> RouteDecision {
        if ctx.fromSharedLink { return .allow }
        guard let prev = ctx.previous, let host = prev.host, site(forHost: host) == .instagram else {
            return .allow  // opened from outside the tab
        }
        let p = segments(prev)
        if p.first?.lowercased() == "direct" { return .allow }
        if let prevReel = reelID(p) {
            // Same reel (query or replaceState change) is fine. A new one is a swipe.
            return prevReel == id ? .allow : .redirect(instagramInbox)
        }
        // Opened from a profile grid or anywhere else: stay where you were.
        return .redirect(prev)
    }

    private static func stories(_ seg: [String], _ ctx: RouteContext) -> RouteDecision {
        guard seg.count >= 2 else { return .redirect(instagramInbox) }
        let owner = seg[1].lowercased()
        if ctx.fromSharedLink { return .allow }
        guard let prev = ctx.previous, let host = prev.host, site(forHost: host) == .instagram else {
            return .allow
        }
        let p = segments(prev).map { $0.lowercased() }
        guard let pFirst = p.first else { return .redirect(instagramInbox) }
        if pFirst == "direct" { return .allow }
        // Story ring on that person's profile.
        if pFirst == owner { return .allow }
        // Moving through one person's stories is fine. Auto-advancing to someone else is not.
        if pFirst == "stories", p.count >= 2, p[1] == owner { return .allow }
        return .redirect(instagramInbox)
    }

    // MARK: - YouTube

    /// `/feed/<name>` pages that are recommendation feeds.
    static let youtubeBlockedFeeds: Set<String> = [
        "", "explore", "trending", "what_to_watch", "storefront", "news_destination", "gaming",
    ]

    static func youtube(_ url: URL, _ ctx: RouteContext) -> RouteDecision {
        let host = url.host?.lowercased() ?? ""
        let seg = segments(url)

        if host == "youtu.be" {
            guard let id = seg.first else { return .redirect(youtubeSubscriptions) }
            return .redirect(watchURL(id, time: queryValue(url, "t")))
        }

        guard let first = seg.first?.lowercased() else {
            return .redirect(youtubeSubscriptions)  // home
        }

        switch first {
        case "shorts":
            guard seg.count >= 2 else { return .redirect(youtubeSubscriptions) }
            // A short someone sent you plays once, as a normal video (no swipe feed).
            if ctx.fromSharedLink || !cameFromYouTube(ctx) {
                return .redirect(watchURL(seg[1], time: nil))
            }
            return .redirect(youtubeSubscriptions)

        case "feed":
            let name = seg.count >= 2 ? seg[1].lowercased() : ""
            return youtubeBlockedFeeds.contains(name) ? .redirect(youtubeSubscriptions) : .allow

        case "gaming", "explore", "trending", "hashtag":
            return .redirect(youtubeSubscriptions)

        default:
            // Channel Shorts tab: /@name/shorts, /channel/<id>/shorts, /c/<name>/shorts
            if seg.count >= 2, seg.last?.lowercased() == "shorts" {
                let kept = seg.dropLast().joined(separator: "/")
                return .redirect(URL(string: "https://m.youtube.com/\(kept)")!)
            }
            return .allow
        }
    }

    private static func cameFromYouTube(_ ctx: RouteContext) -> Bool {
        guard let host = ctx.previous?.host else { return false }
        return site(forHost: host) == .youtube
    }

    static func watchURL(_ id: String, time: String?) -> URL {
        var c = URLComponents(string: "https://m.youtube.com/watch")!
        var items = [URLQueryItem(name: "v", value: id)]
        if let time, !time.isEmpty { items.append(URLQueryItem(name: "t", value: time)) }
        c.queryItems = items
        return c.url!
    }

    // MARK: - Helpers

    static func segments(_ url: URL) -> [String] {
        url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static func queryURL(_ url: URL, _ name: String) -> URL? {
        guard let value = queryValue(url, name), let target = URL(string: value),
              let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return target
    }
}
