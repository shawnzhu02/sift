import XCTest
@testable import Sift

final class RouterTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(string: s)! }

    private func ig(_ url: String, prev: String? = nil, shared: Bool = false) -> RouteDecision {
        Router.decide(u(url), in: .instagram, context: RouteContext(previous: prev.map(u), fromSharedLink: shared))
    }

    private func yt(_ url: String, prev: String? = nil, shared: Bool = false) -> RouteDecision {
        Router.decide(u(url), in: .youtube, context: RouteContext(previous: prev.map(u), fromSharedLink: shared))
    }

    private let inbox = RouteDecision.redirect(Router.instagramInbox)
    private let subs = RouteDecision.redirect(Router.youtubeSubscriptions)

    // MARK: Instagram feeds are blocked

    func testInstagramHomeGoesToInbox() {
        XCTAssertEqual(ig("https://www.instagram.com/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com"), inbox)
        XCTAssertEqual(ig("https://instagram.com/?utm=x"), inbox)
    }

    func testInstagramExploreGoesToInbox() {
        XCTAssertEqual(ig("https://www.instagram.com/explore/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/explore/tags/cats/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/explore/search/"), .allow)
    }

    func testInstagramReelsFeedGoesToInbox() {
        XCTAssertEqual(ig("https://www.instagram.com/reels/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/reels/audio/123/"), inbox)
    }

    // MARK: Instagram allowed pages

    func testInstagramAllowedPages() {
        XCTAssertEqual(ig("https://www.instagram.com/direct/inbox/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/direct/t/1234567/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/accounts/edit/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/accounts/login/?next=%2F"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/someone/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/p/AbC123/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/someone/p/AbC123/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/someone/tagged/"), .allow)
    }

    func testInstagramProfileReelsTabGoesToProfile() {
        XCTAssertEqual(ig("https://www.instagram.com/someone/reels/"),
                       .redirect(u("https://www.instagram.com/someone/")))
    }

    // MARK: Reels from DMs only, one at a time

    func testReelFromDMIsAllowed() {
        XCTAssertEqual(ig("https://www.instagram.com/reel/AAA/", prev: "https://www.instagram.com/direct/t/99/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reels/AAA/", prev: "https://www.instagram.com/direct/t/99/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/friend/reel/AAA/", prev: "https://www.instagram.com/direct/t/99/"), .allow)
    }

    func testSwipeToNextReelGoesToInbox() {
        XCTAssertEqual(ig("https://www.instagram.com/reels/BBB/", prev: "https://www.instagram.com/reel/AAA/"), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/reel/BBB/", prev: "https://www.instagram.com/reels/AAA/"), inbox)
    }

    func testSameReelUpdateIsAllowed() {
        XCTAssertEqual(ig("https://www.instagram.com/reel/AAA/?igsh=1", prev: "https://www.instagram.com/reel/AAA/"), .allow)
    }

    func testReelFromProfileGoesBackToProfile() {
        XCTAssertEqual(ig("https://www.instagram.com/reel/AAA/", prev: "https://www.instagram.com/someone/"),
                       .redirect(u("https://www.instagram.com/someone/")))
    }

    func testReelOpenedFromOutsideIsAllowed() {
        XCTAssertEqual(ig("https://www.instagram.com/reel/AAA/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reel/AAA/", prev: "https://www.instagram.com/someone/", shared: true), .allow)
    }

    // MARK: Stories

    func testStoryFromDMAllowedButNoAutoAdvance() {
        let dm = "https://www.instagram.com/direct/t/99/"
        XCTAssertEqual(ig("https://www.instagram.com/stories/friend/111/", prev: dm), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/stories/friend/112/", prev: "https://www.instagram.com/stories/friend/111/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/stories/stranger/1/", prev: "https://www.instagram.com/stories/friend/112/"), inbox)
    }

    func testStoryFromOwnersProfileAllowed() {
        XCTAssertEqual(ig("https://www.instagram.com/stories/friend/111/", prev: "https://www.instagram.com/friend/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/stories/other/111/", prev: "https://www.instagram.com/friend/"), inbox)
    }

    // MARK: Cross-site and external links

    func testInstagramLinkShimUnwraps() {
        let shim = "https://l.instagram.com/?u=https%3A%2F%2Fyoutu.be%2Fabc&e=x"
        XCTAssertEqual(ig(shim), .switchTab(.youtube, u("https://youtu.be/abc")))
        let ext = "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fa"
        XCTAssertEqual(ig(ext), .openExternal(u("https://example.com/a")))
    }

    func testInstagramAppLinksStayOnWeb() {
        XCTAssertEqual(ig("https://applink.instagram.com/instagram/?ig_mid=X&fall_back_to_web=false"),
                       .redirect(u("https://www.instagram.com/instagram/")))
        XCTAssertEqual(ig("https://applink.instagram.com/"), .redirect(u("https://www.instagram.com/")))
    }

    func testYouTubeLinkInInstagramSwitchesTab() {
        XCTAssertEqual(ig("https://www.youtube.com/shorts/xyz"), .switchTab(.youtube, u("https://www.youtube.com/shorts/xyz")))
    }

    func testLoginHostsStayInTab() {
        XCTAssertEqual(ig("https://www.facebook.com/login/"), .allow)
        XCTAssertEqual(yt("https://accounts.google.com/ServiceLogin"), .allow)
        XCTAssertEqual(yt("https://www.facebook.com/"), .openExternal(u("https://www.facebook.com/")))
    }

    func testAppSchemesBlocked() {
        XCTAssertEqual(ig("instagram://direct-inbox"), .block)
        XCTAssertEqual(yt("youtube://watch?v=1"), .block)
        XCTAssertEqual(yt("about:blank"), .allow)
        XCTAssertEqual(ig("data:text/html,hi"), .block)
        XCTAssertEqual(ig("javascript:alert(1)"), .block)
        XCTAssertEqual(ig("weird-app://x"), .block)
        XCTAssertEqual(ig("mailto:a@b.com"), .openExternal(u("mailto:a@b.com")))
    }

    func testOnlyExactAuthHosts() {
        XCTAssertEqual(yt("https://evil.google.com/"), .openExternal(u("https://evil.google.com/")))
        XCTAssertEqual(ig("https://evil.facebook.com/"), .openExternal(u("https://evil.facebook.com/")))
    }

    // MARK: YouTube feeds are blocked

    func testYouTubeHomeGoesToSubscriptions() {
        XCTAssertEqual(yt("https://m.youtube.com/"), subs)
        XCTAssertEqual(yt("https://www.youtube.com"), subs)
        XCTAssertEqual(yt("https://m.youtube.com/feed/trending"), subs)
        XCTAssertEqual(yt("https://m.youtube.com/feed/explore"), subs)
        XCTAssertEqual(yt("https://m.youtube.com/gaming"), subs)
    }

    func testYouTubeAllowedPages() {
        XCTAssertEqual(yt("https://m.youtube.com/feed/subscriptions"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/feed/library"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/feed/history"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/watch?v=abc"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/results?search_query=calc+2"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/@veritasium"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/@veritasium/videos"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/channel/UC123"), .allow)
        XCTAssertEqual(yt("https://m.youtube.com/playlist?list=PL1"), .allow)
    }

    // MARK: Shorts

    func testSharedShortPlaysAsNormalVideo() {
        XCTAssertEqual(yt("https://www.youtube.com/shorts/xyz", shared: true), .redirect(Router.watchURL("xyz", time: nil)))
        XCTAssertEqual(yt("https://www.youtube.com/shorts/xyz"), .redirect(Router.watchURL("xyz", time: nil)))
    }

    func testShortFromInsideYouTubeGoesToSubscriptions() {
        XCTAssertEqual(yt("https://m.youtube.com/shorts/xyz", prev: "https://m.youtube.com/feed/subscriptions"), subs)
        XCTAssertEqual(yt("https://m.youtube.com/shorts/next", prev: "https://m.youtube.com/watch?v=xyz"), subs)
        XCTAssertEqual(yt("https://m.youtube.com/shorts", prev: "https://m.youtube.com/feed/subscriptions"), subs)
    }

    func testChannelShortsTabGoesToChannel() {
        XCTAssertEqual(yt("https://m.youtube.com/@veritasium/shorts"), .redirect(u("https://m.youtube.com/@veritasium")))
        XCTAssertEqual(yt("https://m.youtube.com/channel/UC123/shorts"), .redirect(u("https://m.youtube.com/channel/UC123")))
    }

    func testYoutuBeLinksBecomeWatchPages() {
        XCTAssertEqual(yt("https://youtu.be/abc?t=42"), .redirect(u("https://m.youtube.com/watch?v=abc&t=42")))
    }

    func testYouTubeRedirectorOpensExternally() {
        let r = "https://m.youtube.com/redirect?event=video_description&q=https%3A%2F%2Fexample.com%2F"
        XCTAssertEqual(yt(r), .openExternal(u("https://example.com/")))
    }

    func testInstagramLinkInYouTubeSwitchesTab() {
        XCTAssertEqual(yt("https://www.instagram.com/someone/"), .switchTab(.instagram, u("https://www.instagram.com/someone/")))
    }
}
