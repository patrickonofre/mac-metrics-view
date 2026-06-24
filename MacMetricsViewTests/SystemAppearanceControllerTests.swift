import XCTest
import AppKit
@testable import MacMetricsView

final class SystemAppearanceControllerTests: XCTestCase {
    func testDarkAquaMapsToDark() {
        let dark = NSAppearance(named: .darkAqua)!
        XCTAssertEqual(SystemAppearanceController.mode(for: dark), .dark)
    }

    func testAquaMapsToLight() {
        let light = NSAppearance(named: .aqua)!
        XCTAssertEqual(SystemAppearanceController.mode(for: light), .light)
    }

    func testNilErrorCodeIsApplied() {
        XCTAssertEqual(SystemAppearanceController.applyResult(errorCode: nil), .applied)
    }

    func testMinus1743IsNotAuthorized() {
        XCTAssertEqual(SystemAppearanceController.applyResult(errorCode: -1743), .notAuthorized)
    }

    func testOtherErrorIsFailed() {
        XCTAssertEqual(SystemAppearanceController.applyResult(errorCode: -600), .failed)
    }
}
