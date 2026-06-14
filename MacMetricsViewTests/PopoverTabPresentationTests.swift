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

    // MARK: - Card order

    func testCardOrder() {
        XCTAssertEqual(
            PopoverTabPresentation.cardOrder,
            [.cpu, .ram, .network, .temperature, .disk, .battery, .tokens]
        )
    }

    func testCardOrderHasNoDuplicates() {
        XCTAssertEqual(Set(PopoverTabPresentation.cardOrder).count, PopoverTabPresentation.cardOrder.count)
    }

    // MARK: - Expandability

    func testExpandableKinds() {
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.tokens))
        XCTAssertTrue(PopoverTabPresentation.isExpandable(.battery))
    }

    func testSummaryOnlyKinds() {
        for kind: MetricCardKind in [.cpu, .ram, .network, .temperature, .disk] {
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
