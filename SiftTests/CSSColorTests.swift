import XCTest
@testable import Sift

final class CSSColorTests: XCTestCase {
    private func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CSSColor.RGBA {
        CSSColor.RGBA(r: r / 255, g: g / 255, b: b / 255, a: a)
    }

    func testRGB() {
        XCTAssertEqual(CSSColor.parse("rgb(15, 15, 15)"), rgba(15, 15, 15))
        XCTAssertEqual(CSSColor.parse("rgba(255, 255, 255, 0.5)"), rgba(255, 255, 255, 0.5))
        XCTAssertEqual(CSSColor.parse("rgb(0 0 0 / 50%)"), rgba(0, 0, 0, 0.5))
    }

    func testHex() {
        XCTAssertEqual(CSSColor.parse("#0f0f0f"), rgba(15, 15, 15))
        XCTAssertEqual(CSSColor.parse("#FFF"), rgba(255, 255, 255))
        XCTAssertEqual(CSSColor.parse("#00000080")?.a ?? 0, 128.0 / 255, accuracy: 0.001)
    }

    func testRejectsJunkAndTransparent() {
        XCTAssertNil(CSSColor.parse("transparent"))
        XCTAssertNil(CSSColor.parse("#12"))
        XCTAssertNil(CSSColor.parse("hsl(0, 0%, 0%)"))
        XCTAssertNil(CSSColor.color("rgba(0, 0, 0, 0)"))
        XCTAssertNotNil(CSSColor.color("#000"))
    }
}
