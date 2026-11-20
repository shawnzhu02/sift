import Foundation

/// How much of a site's short-video feed (Reels, Shorts) Sift lets through.
enum ClipMode: String, Codable, CaseIterable, Identifiable {
    /// Clips open only from a DM or a shared link, one at a time.
    case off
    /// Only clips from accounts you follow or subscribe to. Swiping moves
    /// through them and stops at the last one, never into recommendations.
    case following
    /// The site's whole feed, recommendations included.
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .following: return "Following"
        case .all: return "All"
        }
    }
}

/// Every switch in Settings. The defaults are Sift's strict setup: DMs and
/// Subscriptions, nothing that feeds you more.
struct Features: Codable, Equatable {
    // MARK: Instagram

    /// The home feed, as the Following view (newest posts from people you follow).
    var igFeed = false
    var igReels: ClipMode = .off
    /// Stories (still one person at a time; never auto-advancing to someone else).
    var igStories = true
    /// Profile pages.
    var igProfiles = true
    /// Making posts (Instagram's Create button and pages).
    var igPosting = false
    /// The Explore grid.
    var igExplore = false
    /// Search for people.
    var igSearch = true
    /// The activity / notifications page.
    var igNotifications = true

    // MARK: YouTube

    var ytShorts: ClipMode = .off
    /// The recommended Home feed and trending pages.
    var ytHome = false
    var ytSearch = true
    var ytComments = true
    /// Related videos under a video, and the end screen.
    var ytUpNext = false
    /// Playing the next video on its own when one ends.
    var ytAutoplay = false
    /// Library, history and playlists.
    var ytLibrary = true

    static let strict = Features()

    init() {}

    /// Missing keys (from an older version) keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Features()
        igFeed = try c.decodeIfPresent(Bool.self, forKey: .igFeed) ?? d.igFeed
        igReels = (try? c.decodeIfPresent(ClipMode.self, forKey: .igReels)) ?? d.igReels
        igStories = try c.decodeIfPresent(Bool.self, forKey: .igStories) ?? d.igStories
        igProfiles = try c.decodeIfPresent(Bool.self, forKey: .igProfiles) ?? d.igProfiles
        igPosting = try c.decodeIfPresent(Bool.self, forKey: .igPosting) ?? d.igPosting
        igExplore = try c.decodeIfPresent(Bool.self, forKey: .igExplore) ?? d.igExplore
        igSearch = try c.decodeIfPresent(Bool.self, forKey: .igSearch) ?? d.igSearch
        igNotifications = try c.decodeIfPresent(Bool.self, forKey: .igNotifications) ?? d.igNotifications
        ytShorts = (try? c.decodeIfPresent(ClipMode.self, forKey: .ytShorts)) ?? d.ytShorts
        ytHome = try c.decodeIfPresent(Bool.self, forKey: .ytHome) ?? d.ytHome
        ytSearch = try c.decodeIfPresent(Bool.self, forKey: .ytSearch) ?? d.ytSearch
        ytComments = try c.decodeIfPresent(Bool.self, forKey: .ytComments) ?? d.ytComments
        ytUpNext = try c.decodeIfPresent(Bool.self, forKey: .ytUpNext) ?? d.ytUpNext
        ytAutoplay = try c.decodeIfPresent(Bool.self, forKey: .ytAutoplay) ?? d.ytAutoplay
        ytLibrary = try c.decodeIfPresent(Bool.self, forKey: .ytLibrary) ?? d.ytLibrary
    }

    func clips(_ site: SiteID) -> ClipMode {
        site == .instagram ? igReels : ytShorts
    }

    /// Words for the page's `html[data-sift]` attribute. The CSS and the
    /// hider scripts key off these, so turning a switch on unhides its part.
    func flags(for site: SiteID) -> [String] {
        var f: [String] = []
        switch site {
        case .instagram:
            if igReels == .off { f.append("no-reels") }
            if igReels == .following { f.append("clips-following") }
            if !igExplore { f.append("no-explore") }
            if !igPosting { f.append("no-posting") }
            if !igSearch { f.append("no-search") }
            if !igNotifications { f.append("no-notifications") }
            if !igFeed { f.append("no-feed") }
        case .youtube:
            if ytShorts == .off { f.append("no-shorts") }
            if ytShorts == .following { f.append("clips-following") }
            if !ytHome { f.append("no-home") }
            if !ytSearch { f.append("no-search") }
            if !ytComments { f.append("no-comments") }
            if !ytUpNext { f.append("no-upnext") }
            if !ytAutoplay { f.append("no-autoplay") }
        }
        return f
    }

    /// Plain sentences for Settings, built from the current switches.
    func blockedSummary(for site: SiteID) -> String {
        var parts: [String] = []
        switch site {
        case .instagram:
            parts.append(igFeed ? "Home shows only people you follow." : "Home goes to your inbox.")
            if !igExplore { parts.append("Explore is off.") }
            switch igReels {
            case .off: parts.append("A reel opens only from a DM, one at a time.")
            case .following: parts.append("Reels play only from people you follow, and stop after the last one.")
            case .all: parts.append("Reels are fully on.")
            }
            parts.append(igStories ? "Stories never jump to someone else's." : "Stories are off.")
            if !igProfiles { parts.append("Profiles are off.") }
            parts.append("\"Suggested for you\" is always hidden.")
        case .youtube:
            parts.append(ytHome ? "Home recommendations are on." : "Home and trending go to Subscriptions.")
            switch ytShorts {
            case .off: parts.append("Shorts are hidden. A shared Short plays once as a normal video.")
            case .following: parts.append("Shorts play only from channels you subscribe to, and stop after the last one.")
            case .all: parts.append("Shorts are fully on.")
            }
            if !ytUpNext { parts.append("Up next and the end screen are hidden.") }
            if !ytAutoplay { parts.append("Autoplay is off.") }
            if !ytComments { parts.append("Comments are hidden.") }
            parts.append("Ads and \"open app\" prompts are always hidden.")
        }
        return parts.joined(separator: " ")
    }
}

/// Keeps the switches in UserDefaults and tells the app when they change.
@MainActor
final class FeatureStore: ObservableObject {
    static let key = "features.v1"

    @Published var features: Features {
        didSet {
            guard features != oldValue else { return }
            save()
            onChange?(oldValue, features)
        }
    }

    /// Called after a change, with the old and new switches.
    var onChange: ((Features, Features) -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Features.self, from: data) {
            features = saved
        } else {
            features = .strict
        }
    }

    func reset() {
        features = .strict
    }

    private func save() {
        if let data = try? JSONEncoder().encode(features) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
