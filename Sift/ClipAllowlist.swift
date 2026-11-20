import Foundation

/// Clip ids (YouTube Shorts, Instagram Reels) seen on pages that list only
/// people you follow: the Subscriptions feed, a subscribed channel's Shorts
/// tab, Instagram's Following feed, a followed profile's grid.
///
/// In "Following" mode a clip plays only if it is on this list, and swiping
/// past one moves to the next listed clip instead of a recommendation.
/// Newest first. Ids expire after 7 days.
struct ClipList: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: String
        var seen: Date
    }

    var entries: [Entry] = []

    static let maxCount = 300
    static let lifetime: TimeInterval = 7 * 24 * 3600

    var ids: [String] { entries.map(\.id) }

    func contains(_ id: String) -> Bool {
        entries.contains { $0.id == id }
    }

    /// Adds ids found on one page, in page order, ahead of older ones.
    /// Ids already listed keep their place.
    mutating func add(_ found: [String], now: Date = Date()) {
        var fresh: [Entry] = []
        var seenNow = Set<String>()
        for id in found where !id.isEmpty && !seenNow.contains(id) && !contains(id) {
            seenNow.insert(id)
            fresh.append(Entry(id: id, seen: now))
        }
        entries = fresh + entries
        prune(now: now)
    }

    mutating func prune(now: Date = Date()) {
        entries.removeAll { now.timeIntervalSince($0.seen) > Self.lifetime }
        if entries.count > Self.maxCount { entries = Array(entries.prefix(Self.maxCount)) }
    }

    /// The listed clip after `id`, for a swipe forward.
    func next(after id: String) -> String? {
        guard let i = entries.firstIndex(where: { $0.id == id }), i + 1 < entries.count else { return nil }
        return entries[i + 1].id
    }
}

/// Both sites' lists, saved in UserDefaults.
@MainActor
final class ClipAllowlist: ObservableObject {
    @Published private(set) var lists: [SiteID: ClipList] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for site in SiteID.allCases {
            if let data = defaults.data(forKey: Self.key(site)),
               var list = try? JSONDecoder().decode(ClipList.self, from: data) {
                list.prune()
                lists[site] = list
            }
        }
    }

    func list(_ site: SiteID) -> ClipList {
        lists[site] ?? ClipList()
    }

    func add(_ ids: [String], for site: SiteID) {
        var list = self.list(site)
        let before = list
        list.add(ids)
        guard list != before else { return }
        lists[site] = list
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.key(site))
        }
    }

    private static func key(_ site: SiteID) -> String { "clips.\(site.rawValue)" }
}
