import XCTest
@testable import MacMetricsView

/// Covers the settings RAM picker presentation seam: the ordered mode list and
/// per-mode labels the `.menu` dropdown renders (ADR-002), kept testable without
/// constructing the SwiftUI view.
final class RAMMenuBarPickerTests: XCTestCase {

    func testPickerOrderIsUsedTotalFirst() {
        XCTAssertEqual(
            MetricDisplaySettings.RAMMenuBarMetric.menuBarPickerOrder,
            [.usedTotal, .appMemory, .pressure]
        )
    }

    func testEveryModeHasANonEmptyLabel() {
        for mode in MetricDisplaySettings.RAMMenuBarMetric.menuBarPickerOrder {
            XCTAssertFalse(mode.menuBarPickerLabel(.english).isEmpty)
            XCTAssertFalse(mode.menuBarPickerLabel(.portuguese).isEmpty)
        }
    }

    func testModeLabelsAreDistinct() {
        let labels = MetricDisplaySettings.RAMMenuBarMetric.menuBarPickerOrder
            .map { $0.menuBarPickerLabel(.english) }
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testDefaultSelectionSurfacesUsedTotal() {
        XCTAssertEqual(MetricDisplaySettings().ramMenuBarMetric, .usedTotal)
    }
}
