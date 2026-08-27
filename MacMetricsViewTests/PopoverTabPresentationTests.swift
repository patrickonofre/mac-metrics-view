import XCTest
@testable import MacMetricsView

final class PopoverTabPresentationTests: XCTestCase {

    // MARK: - Tabs

    func testTabsOrder() {
        XCTAssertEqual(PopoverTabPresentation.tabs, [.metrics, .settings, .actions])
    }

    func testTabsCoversAllCases() {
        XCTAssertEqual(Set(PopoverTabPresentation.tabs), Set(PopoverTab.allCases))
    }

    // MARK: - Titles

    func testMetricsTitleReusesMetricsPlaceholder() {
        XCTAssertEqual(PopoverTabPresentation.title(.metrics, .english), Strings.metricsPlaceholder(.english))
        XCTAssertEqual(PopoverTabPresentation.title(.metrics, .portuguese), Strings.metricsPlaceholder(.portuguese))
        XCTAssertEqual(PopoverTabPresentation.title(.metrics, .english), "Metrics")
        XCTAssertEqual(PopoverTabPresentation.title(.metrics, .portuguese), "Métricas")
    }

    func testSettingsTitle() {
        XCTAssertEqual(PopoverTabPresentation.title(.settings, .english), "Settings")
        XCTAssertEqual(PopoverTabPresentation.title(.settings, .portuguese), "Ajustes")
    }

    func testActionsTitle() {
        XCTAssertEqual(PopoverTabPresentation.title(.actions, .english), "Actions")
        XCTAssertEqual(PopoverTabPresentation.title(.actions, .portuguese), "Ações")
    }

    func testTitlesAreNonEmptyInBothLanguages() {
        for tab in PopoverTabPresentation.tabs {
            XCTAssertFalse(PopoverTabPresentation.title(tab, .english).isEmpty)
            XCTAssertFalse(PopoverTabPresentation.title(tab, .portuguese).isEmpty)
        }
    }

    // MARK: - Metric order

    func testMetricOrder() {
        XCTAssertEqual(
            PopoverTabPresentation.metricOrder,
            [.cpu, .gpu, .ram, .network, .temperature, .disk, .battery]
        )
    }

    func testMetricOrderHasNoDuplicates() {
        XCTAssertEqual(Set(PopoverTabPresentation.metricOrder).count, PopoverTabPresentation.metricOrder.count)
    }

    func testLegacyCardOrderMatchesMetricOrderDuringGridMigration() {
        XCTAssertEqual(PopoverTabPresentation.cardOrder, PopoverTabPresentation.metricOrder)
    }

    // MARK: - Expandability

    func testExpandableKinds() {
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.battery))
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.cpu))
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.ram))
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.network))
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.disk))
    }

    func testSummaryOnlyKinds() {
        for kind: MetricCardKind in [.temperature, .gpu] {
            XCTAssertFalse(PopoverTabPresentation.isExpandable(kind))
        }
    }

    // MARK: - Severity color role

    func testColorRoleMapping() {
        XCTAssertEqual(PopoverTabPresentation.colorRole(for: .normal), .normal)
        XCTAssertEqual(PopoverTabPresentation.colorRole(for: .elevatedCPU), .elevated)
        XCTAssertEqual(PopoverTabPresentation.colorRole(for: .highCPU), .high)
    }
}
