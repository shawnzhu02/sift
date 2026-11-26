import XCTest
@testable import Sift

/// The Settings switches: saving, and what each one lets through.
final class FeaturesTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(string: s)! }

    private func ig(_ url: String, _ f: Features, clips: [String] = [], prev: String? = nil, shared: Bool = false) -> RouteDecision {
        var list = ClipList()
        list.add(clips)
        return Router.decide(u(url), in: .instagram,
                             context: RouteContext(previous: prev.map(u), fromSharedLink: shared),
                             policy: RoutePolicy(features: f, clips: list))
    }

    private func yt(_ url: String, _ f: Features, clips: [String] = [], prev: String? = nil, shared: Bool = false) -> RouteDecision {
        var list = ClipList()
        list.add(clips)
        return Router.decide(u(url), in: .youtube,
                             context: RouteContext(previous: prev.map(u), fromSharedLink: shared),
                             policy: RoutePolicy(features: f, clips: list))
    }

    private let inbox = RouteDecision.redirect(Router.instagramInbox)
    private let subs = RouteDecision.redirect(Router.youtubeSubscriptions)

    private func with(_ change: (inout Features) -> Void) -> Features {
        var f = Features.strict
        change(&f)
        return f
    }

    // MARK: Saving

    func testStrictDefaults() {
        let f = Features.strict
        XCTAssertEqual(f.igReels, .off)
        XCTAssertEqual(f.ytShorts, .off)
        XCTAssertFalse(f.igFeed)
        XCTAssertFalse(f.igExplore)
        XCTAssertFalse(f.ytHome)
        XCTAssertFalse(f.ytUpNext)
        XCTAssertFalse(f.ytAutoplay)
        XCTAssertEqual(SiftTab.visible(f), [.messages, .subscriptions, .settings])
    }

    func testCodableRoundTrip() throws {
        let f = with { $0.igReels = .following; $0.ytShorts = .all; $0.igPosting = true; $0.ytComments = false }
        let data = try JSONEncoder().encode(f)
        XCTAssertEqual(try JSONDecoder().decode(Features.self, from: data), f)
    }

    func testOldSavedDataKeepsDefaultsForNewKeys() throws {
        let data = Data(#"{"igFeed": true}"#.utf8)
        let f = try JSONDecoder().decode(Features.self, from: data)
        XCTAssertTrue(f.igFeed)
        XCTAssertEqual(f.ytShorts, .off)
        XCTAssertTrue(f.ytComments)
    }

    @MainActor
    func testStoreSavesAndLoads() {
        let defaults = UserDefaults(suiteName: "sift.tests.\(UUID().uuidString)")!
        let store = FeatureStore(defaults: defaults)
        store.features.ytShorts = .following
        XCTAssertEqual(FeatureStore(defaults: defaults).features.ytShorts, .following)
        store.reset()
        XCTAssertEqual(FeatureStore(defaults: defaults).features, .strict)
    }

    func testTabsFollowSwitches() {
        XCTAssertEqual(SiftTab.visible(with { $0.igFeed = true }), [.messages, .feed, .subscriptions, .settings])
        XCTAssertEqual(SiftTab.visible(with { $0.ytShorts = .following }), [.messages, .clips, .subscriptions, .settings])
    }

    func testFlags() {
        XCTAssertTrue(Features.strict.flags(for: .youtube).contains("no-shorts"))
        XCTAssertFalse(with { $0.ytShorts = .all }.flags(for: .youtube).contains("no-shorts"))
        XCTAssertTrue(with { $0.ytShorts = .following }.flags(for: .youtube).contains("clips-following"))
        XCTAssertTrue(with { $0.ytComments = false }.flags(for: .youtube).contains("no-comments"))
        XCTAssertFalse(with { $0.igPosting = true }.flags(for: .instagram).contains("no-posting"))
    }

    // MARK: Instagram switches

    func testFeedShowsOnlyFollowing() {
        let f = with { $0.igFeed = true }
        XCTAssertEqual(ig("https://www.instagram.com/", f), .redirect(Router.instagramFollowing))
        XCTAssertEqual(ig("https://www.instagram.com/?variant=following", f), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/?variant=following", .strict), inbox)
    }

    func testExploreAndSearchSwitches() {
        XCTAssertEqual(ig("https://www.instagram.com/explore/", with { $0.igExplore = true }), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/explore/search/", with { $0.igSearch = false }), inbox)
    }

    func testPostingSwitch() {
        XCTAssertEqual(ig("https://www.instagram.com/create/select/", .strict), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/create/select/", with { $0.igPosting = true }), .allow)
    }

    func testProfilesSwitch() {
        XCTAssertEqual(ig("https://www.instagram.com/someone/", with { $0.igProfiles = false }), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/p/AbC/", with { $0.igProfiles = false }), .allow)
    }

    func testStoriesAndNotificationsSwitches() {
        XCTAssertEqual(ig("https://www.instagram.com/stories/friend/1/", with { $0.igStories = false },
                          prev: "https://www.instagram.com/direct/t/9/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/accounts/activity/", with { $0.igNotifications = false }), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/accounts/activity/", .strict), .allow)
    }

    func testFeedLimitFlagsAndDefaults() {
        XCTAssertFalse(Features.strict.flags(for: .instagram).contains { $0.hasPrefix("feed-") })
        let f = with { $0.igFeed = true; $0.igFeedMax = 20 }
        XCTAssertTrue(f.flags(for: .instagram).contains("feed-caughtup"))
        XCTAssertTrue(f.flags(for: .instagram).contains("feed-max-20"))
        let none = with { $0.igFeed = true; $0.igFeedCaughtUp = false; $0.igFeedMax = 0 }
        XCTAssertFalse(none.flags(for: .instagram).contains { $0.hasPrefix("feed-") })
    }

    func testOldSavedSettingsKeepFeedLimitDefaults() throws {
        let old = Data(#"{"igFeed":true,"igPosting":true}"#.utf8)
        let f = try JSONDecoder().decode(Features.self, from: old)
        XCTAssertTrue(f.igFeed)
        XCTAssertTrue(f.igFeedCaughtUp)
        XCTAssertEqual(f.igFeedMax, 30)
    }

    func testEverythingButReelsPreset() {
        let f = Features.everythingButReels
        XCTAssertTrue(f.igFeed && f.igPosting && f.igStories && f.igProfiles && f.igSearch && f.igNotifications)
        XCTAssertEqual(f.igReels, .off)
        XCTAssertFalse(f.igExplore)
        XCTAssertEqual(ig("https://www.instagram.com/", f), .redirect(Router.instagramFollowing))
        XCTAssertEqual(ig("https://www.instagram.com/create/select/", f), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reels/", f), inbox)
        // Applying it leaves YouTube alone.
        let mixed = with { $0.ytHome = true }.applyingInstagram(from: f)
        XCTAssertTrue(mixed.ytHome)
        XCTAssertTrue(mixed.igFeed)
    }

    func testOnlyChangedPagesReload() {
        let before = Features.strict
        let afterYT = with { $0.ytHome = true }
        XCTAssertEqual(Site.flags(for: .messages, features: before), Site.flags(for: .messages, features: afterYT))
        XCTAssertNotEqual(Site.flags(for: .subscriptions, features: before), Site.flags(for: .subscriptions, features: afterYT))
    }

    func testNotificationsPageFollowsSwitch() {
        XCTAssertEqual(ig("https://www.instagram.com/notifications/", with { $0.igNotifications = false }), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/notifications/", .strict), .allow)
    }

    func testReelsAll() {
        let f = with { $0.igReels = .all }
        XCTAssertEqual(ig("https://www.instagram.com/reels/", f), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reels/BBB/", f, prev: "https://www.instagram.com/reels/AAA/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/someone/reels/", f), .allow)
    }

    func testReelsFollowingSwipesThroughListOnly() {
        let f = with { $0.igReels = .following }
        let list = ["A1", "A2", "A3"]
        // Listed reels play, and swiping back to one is fine.
        XCTAssertEqual(ig("https://www.instagram.com/reel/A2/", f, clips: list, prev: "https://www.instagram.com/reel/A1/"), .allow)
        // Swiping onto a recommendation jumps to the next listed reel instead.
        XCTAssertEqual(ig("https://www.instagram.com/reel/ZZZ/", f, clips: list, prev: "https://www.instagram.com/reel/A1/"),
                       .redirect(Router.reelURL("A2")))
        // After the last listed reel it stays put.
        XCTAssertEqual(ig("https://www.instagram.com/reel/ZZZ/", f, clips: list, prev: "https://www.instagram.com/reel/A3/"),
                       .redirect(u("https://www.instagram.com/reel/A3/")))
        // The endless feed goes to the Following view.
        XCTAssertEqual(ig("https://www.instagram.com/reels/", f, clips: list), .redirect(Router.instagramFollowing))
        // A reel sent in a DM still opens.
        XCTAssertEqual(ig("https://www.instagram.com/reel/ZZZ/", f, clips: list, prev: "https://www.instagram.com/direct/t/1/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reel/ZZZ/", f, clips: list, shared: true), .allow)
    }

    // MARK: YouTube switches

    func testYouTubeHomeSearchLibrary() {
        XCTAssertEqual(yt("https://m.youtube.com/", with { $0.ytHome = true }), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/feed/trending", with { $0.ytHome = true }), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/results?search_query=x", with { $0.ytSearch = false }), subs)
        XCTAssertEqual(yt("https://m.youtube.com/feed/history", with { $0.ytLibrary = false }), subs)
        XCTAssertEqual(yt("https://m.youtube.com/feed/history", .strict), .allow)
    }

    func testShortsAll() {
        let f = with { $0.ytShorts = .all }
        XCTAssertEqual(yt("https://m.youtube.com/shorts/x1", f, prev: "https://m.youtube.com/shorts/x0"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/@chan/shorts", f), .allow)
    }

    func testShortsFollowingSwipesThroughListOnly() {
        let f = with { $0.ytShorts = .following }
        let list = ["s1", "s2"]
        XCTAssertEqual(yt("https://m.youtube.com/shorts/s2", f, clips: list, prev: "https://m.youtube.com/shorts/s1"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/shorts/rec", f, clips: list, prev: "https://m.youtube.com/shorts/s1"),
                       .redirect(Router.shortURL("s2")))
        XCTAssertEqual(yt("https://m.youtube.com/shorts/rec", f, clips: list, prev: "https://m.youtube.com/shorts/s2"),
                       .redirect(u("https://m.youtube.com/shorts/s2")))
        // A short from a channel you don't follow, tapped inside YouTube: stay put.
        XCTAssertEqual(yt("https://m.youtube.com/shorts/rec", f, clips: list, prev: "https://m.youtube.com/results?search_query=x"),
                       .redirect(u("https://m.youtube.com/results?search_query=x")))
        // A shared one plays once as a normal video.
        XCTAssertEqual(yt("https://m.youtube.com/shorts/rec", f, clips: list, shared: true),
                       .redirect(Router.watchURL("rec", time: nil)))
        // Channel Shorts tabs stay open so Sift can find your subscriptions' Shorts.
        XCTAssertEqual(yt("https://m.youtube.com/@chan/shorts", f), .allow)
    }

    // MARK: Clip list

    func testClipListOrderAndNext() {
        var list = ClipList()
        list.add(["a", "b"])
        list.add(["c", "a"])
        XCTAssertEqual(list.ids, ["c", "a", "b"])
        XCTAssertEqual(list.next(after: "a"), "b")
        XCTAssertNil(list.next(after: "b"))
    }

    func testClipListExpires() {
        var list = ClipList()
        let old = Date().addingTimeInterval(-8 * 24 * 3600)
        list.add(["old"], now: old)
        list.add(["new"])
        XCTAssertEqual(list.ids, ["new"])
    }

    func testClipIDs() {
        XCTAssertEqual(Router.clipID(u("https://m.youtube.com/shorts/abc")), "abc")
        XCTAssertEqual(Router.clipID(u("https://www.instagram.com/someone/reel/R1/")), "R1")
        XCTAssertNil(Router.clipID(u("https://m.youtube.com/watch?v=abc")))
    }
}
