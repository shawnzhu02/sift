import XCTest

/// Instagram's inbox is a fixed full-height layout with an inner scrolling list.
/// Taps on it must land on the row that is drawn under the finger.
final class TapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testInstagramRowsTapWhereDrawn() {
        let app = XCUIApplication()
        app.launchEnvironment["SIFT_TEST_PAGE"] = "1"
        app.launch()

        for n in [3, 8] {
            let row = app.staticTexts["Row \(n)"]
            XCTAssertTrue(row.waitForExistence(timeout: 45), "Row \(n) never appeared")
            row.tap()
            let status = app.staticTexts["clicked \(n)"]
            if !status.waitForExistence(timeout: 5) {
                let got = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'clicked'")).firstMatch
                XCTFail("Tapped Row \(n) but the page registered: \(got.exists ? got.label : "nothing")")
            }
        }
    }
}
