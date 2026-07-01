import XCTest
@testable import MacMetricsView

final class LocalizationGPUKeysTests: XCTestCase {
    func testGPULabelResolvesNonEmptyInBothLanguages() {
        XCTAssertFalse(Strings.gpu(.english).isEmpty)
        XCTAssertFalse(Strings.gpu(.portuguese).isEmpty)
    }

    func testGPULabelIsTheAcronymInBothLanguages() {
        // "GPU" is a universal acronym — identical in PT-BR and EN (mirrors how the
        // menu-bar/card label reads).
        XCTAssertEqual(Strings.gpu(.english), "GPU")
        XCTAssertEqual(Strings.gpu(.portuguese), "GPU")
    }
}
