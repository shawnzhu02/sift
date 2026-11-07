import XCTest

/// Instagram's inbox is a fixed full-height layout with an inner scrolling list.
/// A tap must land on the row that is *drawn* under the finger. Each test row
/// has its own background color (red channel = row * 8), so the screenshot
/// tells which row is drawn at a point, independent of accessibility frames.
final class TapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testInstagramRowsTapWhereDrawn() throws {
        try checkTaps(page: "1", scroll: false)
    }

    func testDocumentScrollTapsWhereDrawn() throws {
        try checkTaps(page: "2", scroll: true)
    }

    private func checkTaps(page: String, scroll: Bool) throws {
        let app = XCUIApplication()
        app.launchEnvironment["SIFT_TEST_PAGE"] = page
        app.launch()
        XCTAssertTrue(app.staticTexts["Row 3"].waitForExistence(timeout: 45), "test page never loaded")
        sleep(1)
        if scroll {
            app.webViews.firstMatch.swipeUp(velocity: .slow)
            sleep(2)
        }

        let window = app.windows.firstMatch.frame
        for fraction in [0.35, 0.55, 0.75] {
            let point = CGPoint(x: window.width * 0.8, y: window.height * fraction)
            let shot = XCUIScreen.main.screenshot().image
            let drawn = try XCTUnwrap(row(at: point, in: shot), "no test row drawn at \(point)")

            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y))
                .tap()

            let status = app.staticTexts["clicked \(drawn)"]
            if !status.waitForExistence(timeout: 5) {
                let got = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'clicked'")).firstMatch
                XCTFail("Finger on drawn Row \(drawn) at y=\(Int(point.y)), page registered: \(got.exists ? got.label : "nothing")")
            }
        }
    }

    /// Reads the pixel at a point (in points) and maps its red channel to a row.
    private func row(at point: CGPoint, in image: UIImage) -> Int? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / image.size.width
        let px = Int(point.x * scale), py = Int(point.y * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: -px, y: py - cg.height + 1, width: cg.width, height: cg.height))
        let (r, g, b) = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        // Rows are rgb(n * 8, 120, 60).
        guard abs(g - 120) <= 12, abs(b - 60) <= 12 else { return nil }
        let n = Int((Double(r) / 8).rounded())
        return (1...30).contains(n) ? n : nil
    }
}
