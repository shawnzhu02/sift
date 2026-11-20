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

/// The switches and the following-only clip list a decision depends on.
struct RoutePolicy: Equatable {
    var features: Features
    /// Clips from people you follow, for the tab's site.
    var clips: ClipList

    init(features: Features = .strict, clips: ClipList = ClipList()) {
        self.features = features
        self.clips = clips
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
    /// Instagram's home feed limited to people you follow, newest first.
    static let instagramFollowing = URL(string: "https://www.instagram.com/?variant=following")!

    static func reelURL(_ id: String) -> URL {
        URL(string: "https://www.instagram.com/reel/\(id)/")!
    }

    static func shortURL(_ id: String) -> URL {
        URL(string: "https://m.youtube.com/shorts/\(id)")!
    }

    static func start(for site: SiteID) -> URL {
        switch site {
        case .instagram: return instagramInbox
        case .youtube: return youtubeSubscriptions
        }
    }

    // MARK: - Entry point

    static func decide(
        _ url: URL,
        in tab: SiteID,
        context: RouteContext = RouteContext(),
        policy: RoutePolicy = RoutePolicy()
    ) -> RouteDecision {
        guard let scheme = url.scheme?.lowercased() else { return .allow }

        if scheme != "http" && scheme != "https" {
            switch scheme {
            case "about", "blob":
                return .allow
            case "mailto", "tel", "sms":
                return .openExternal(url)
            default:
                // data:/javascript: pages, app schemes (instagram://, youtube://)
                // and anything else: never load or hand off.
                return .block
            }
        }

        guard let host = url.host?.lowercased() else { return .allow }

        if let target = unwrapRedirect(url) {
            return crossing(to: target, from: tab)
        }

        guard let site = site(forHost: host) else {
            return isAuthHost(host, for: tab) || isAuthPage(url, for: tab) ? .allow : .openExternal(url)
        }
        if site != tab {
            return .switchTab(site, url)
        }

        switch tab {
        case .instagram: return instagram(url, context, policy)
        case .youtube: return youtube(url, context, policy)
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

    /// Exact login and account hosts each site needs inside its own tab.
    static let authHosts: [SiteID: Set<String>] = [
        .instagram: ["www.facebook.com", "m.facebook.com", "auth.meta.com", "accountscenter.meta.com"],
        .youtube: ["accounts.google.com", "consent.google.com", "myaccount.google.com", "gds.google.com"],
    ]

    static func isAuthHost(_ host: String, for tab: SiteID) -> Bool {
        authHosts[tab]?.contains(host.lowercased()) ?? false
    }

    /// Google sign-in sometimes passes through www.google.com. Only its login
    /// paths load in the YouTube tab; search and everything else go to Safari.
    static let googleLoginPaths = ["/accounts", "/signin", "/sorry", "/recaptcha", "/gsi"]

    static func isAuthPage(_ url: URL, for tab: SiteID) -> Bool {
        guard tab == .youtube, url.host?.lowercased() == "www.google.com" else { return false }
        let path = url.path.lowercased()
        return googleLoginPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Login pages that the Connect buttons open.
    static func loginURL(for site: SiteID) -> URL {
        switch site {
        case .instagram:
            return URL(string: "https://www.instagram.com/accounts/login/?next=%2Fdirect%2Finbox%2F")!
        case .youtube:
            return URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Dm%26next%3D%252Ffeed%252Fsubscriptions")!
        }
    }

    /// Link-wrapping redirectors: returns the real destination.
    static func unwrapRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path

        if host == "l.instagram.com" {
            return queryURL(url, "u")
        }
        // "Open in app" links: keep them on the website.
        if host == "applink.instagram.com" {
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            return URL(string: "https://www.instagram.com" + (path.isEmpty ? "/" : path))
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
        "create",
    ]

    static func instagram(_ url: URL, _ ctx: RouteContext, _ policy: RoutePolicy = RoutePolicy()) -> RouteDecision {
        let f = policy.features
        let seg = segments(url)
        guard let first = seg.first?.lowercased() else {
            // Home. With the feed (or following-only Reels) on, only the
            // Following view, never the recommended one.
            guard f.igFeed || f.igReels != .off else { return .redirect(instagramInbox) }
            return queryValue(url, "variant") == "following" ? .allow : .redirect(instagramFollowing)
        }

        switch first {
        case "explore":
            // Search for people is its own switch. The explore grid is another.
            if seg.count >= 2, seg[1].lowercased() == "search" {
                return f.igSearch ? .allow : .redirect(instagramInbox)
            }
            return f.igExplore ? .allow : .redirect(instagramInbox)

        case "reels":
            // `/reels/` is the endless feed. `/reels/<id>/` is one reel.
            // `/reels/audio/<id>/` lists reels for a sound.
            guard seg.count >= 2, seg[1].lowercased() != "audio" else {
                switch f.igReels {
                case .all: return .allow
                case .following: return .redirect(instagramFollowing)
                case .off: return .redirect(instagramInbox)
                }
            }
            return reel(id: seg[1], ctx, policy)

        case "reel", "tv":
            guard seg.count >= 2 else { return .redirect(instagramInbox) }
            return reel(id: seg[1], ctx, policy)

        case "stories":
            guard f.igStories else { return .redirect(instagramInbox) }
            return stories(seg, ctx)

        case "create":
            return f.igPosting ? .allow : .redirect(instagramInbox)

        case "accounts":
            if seg.count >= 2, seg[1].lowercased() == "activity" {
                return f.igNotifications ? .allow : .redirect(instagramInbox)
            }
            return .allow

        default:
            guard !instagramReserved.contains(first) else { return .allow }
            guard seg.count >= 2 else {
                // A profile page.
                return f.igProfiles ? .allow : .redirect(instagramInbox)
            }
            let second = seg[1].lowercased()
            // Newer username-prefixed links: /<user>/reel/<id>/
            if (second == "reel" || second == "reels"), seg.count >= 3 {
                return reel(id: seg[2], ctx, policy)
            }
            // A profile's Reels tab: back to the profile grid unless Reels are on.
            if second == "reels" {
                return f.igReels == .off ? .redirect(URL(string: "https://www.instagram.com/\(seg[0])/")!) : .allow
            }
            return .allow
        }
    }

    /// One reel, by the Reels switch.
    private static func reel(id: String, _ ctx: RouteContext, _ policy: RoutePolicy) -> RouteDecision {
        switch policy.features.igReels {
        case .off:
            return singleReel(id: id, ctx)
        case .all:
            return .allow
        case .following:
            if policy.clips.contains(id) || ctx.fromSharedLink { return .allow }
            guard let prev = ctx.previous, let host = prev.host, site(forHost: host) == .instagram else {
                return .allow  // opened from outside the tab
            }
            let p = segments(prev)
            if p.first?.lowercased() == "direct" { return .allow }
            if let prevReel = reelID(p) {
                if prevReel == id { return .allow }
                // A swipe: on to the next reel from someone you follow, or stay on the last one.
                if let next = policy.clips.next(after: prevReel) { return .redirect(reelURL(next)) }
                return .redirect(prev)
            }
            // Someone you don't follow: stay where you were.
            return .redirect(prev)
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

    /// `/feed/<name>` pages that are your own library.
    static let youtubeLibraryFeeds: Set<String> = ["library", "history", "playlists", "you"]

    static func youtube(_ url: URL, _ ctx: RouteContext, _ policy: RoutePolicy = RoutePolicy()) -> RouteDecision {
        let f = policy.features
        let host = url.host?.lowercased() ?? ""
        let seg = segments(url)

        if host == "youtu.be" {
            guard let id = seg.first else { return .redirect(youtubeSubscriptions) }
            return .redirect(watchURL(id, time: queryValue(url, "t")))
        }

        guard let first = seg.first?.lowercased() else {
            return f.ytHome ? .allow : .redirect(youtubeSubscriptions)  // home
        }

        switch first {
        case "shorts":
            guard seg.count >= 2 else {
                return f.ytShorts == .all ? .allow : .redirect(youtubeSubscriptions)
            }
            return short(id: seg[1], ctx, policy)

        case "feed":
            let name = seg.count >= 2 ? seg[1].lowercased() : ""
            if youtubeBlockedFeeds.contains(name) { return f.ytHome ? .allow : .redirect(youtubeSubscriptions) }
            if youtubeLibraryFeeds.contains(name) { return f.ytLibrary ? .allow : .redirect(youtubeSubscriptions) }
            return .allow

        case "gaming", "explore", "trending", "hashtag":
            return f.ytHome ? .allow : .redirect(youtubeSubscriptions)

        case "results":
            return f.ytSearch ? .allow : .redirect(youtubeSubscriptions)

        default:
            // Channel Shorts tab: /@name/shorts, /channel/<id>/shorts, /c/<name>/shorts
            if seg.count >= 2, seg.last?.lowercased() == "shorts", f.ytShorts == .off {
                let kept = seg.dropLast().joined(separator: "/")
                return .redirect(URL(string: "https://m.youtube.com/\(kept)")!)
            }
            return .allow
        }
    }

    /// One Short, by the Shorts switch.
    private static func short(id: String, _ ctx: RouteContext, _ policy: RoutePolicy) -> RouteDecision {
        switch policy.features.ytShorts {
        case .off:
            // A short someone sent you plays once, as a normal video (no swipe feed).
            if ctx.fromSharedLink || !cameFromYouTube(ctx) {
                return .redirect(watchURL(id, time: nil))
            }
            return .redirect(youtubeSubscriptions)
        case .all:
            return .allow
        case .following:
            if policy.clips.contains(id) { return .allow }
            guard !ctx.fromSharedLink, cameFromYouTube(ctx), let prev = ctx.previous else {
                return .redirect(watchURL(id, time: nil))
            }
            let p = segments(prev)
            if p.first?.lowercased() == "shorts", p.count >= 2 {
                if p[1] == id { return .allow }
                // A swipe: on to the next Short from a channel you subscribe to, or stay on the last one.
                if let next = policy.clips.next(after: p[1]) { return .redirect(shortURL(next)) }
                return .redirect(prev)
            }
            // A channel you don't subscribe to: stay where you were.
            return .redirect(prev)
        }
    }

    /// The clip id in a URL (a Reel or a Short), if it is one.
    static func clipID(_ url: URL) -> String? {
        guard let host = url.host, let site = site(forHost: host) else { return nil }
        let seg = segments(url)
        switch site {
        case .instagram:
            return reelID(seg)
        case .youtube:
            guard seg.first?.lowercased() == "shorts", seg.count >= 2 else { return nil }
            return seg[1]
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
