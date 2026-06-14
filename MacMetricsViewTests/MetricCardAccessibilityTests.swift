import XCTest
@testable import MacMetricsView

final class MetricCardAccessibilityTests: XCTestCase {

    // MARK: - Label composition

    func testLabelOmitsSeveritySuffixForNormal() {
        XCTAssertEqual(
            MetricCardAccessibility.label(title: "CPU", value: "12%", severity: .normal, .english),
            "CPU, 12%"
        )
    }

    func testLabelAppendsElevatedSeverity() {
        XCTAssertEqual(
            MetricCardAccessibility.label(title: "CPU", value: "85%", severity: .elevatedCPU, .english),
            "CPU, 85%, Elevated"
        )
    }

    func testLabelAppendsHighSeverity() {
        XCTAssertEqual(
            MetricCardAccessibility.label(title: "CPU", value: "95%", severity: .highCPU, .english),
            "CPU, 95%, High"
        )
    }

    func testLabelLocalizesSeverityInPortuguese() {
        XCTAssertEqual(
            MetricCardAccessibility.label(title: "CPU", value: "85%", severity: .elevatedCPU, .portuguese),
            "CPU, 85%, Elevado"
        )
    }

    // MARK: - Expansion wording

    func testExpansionLabelReflectsState() {
        XCTAssertEqual(MetricCardAccessibility.expansionLabel(isExpanded: false, .english), "Expand")
        XCTAssertEqual(MetricCardAccessibility.expansionLabel(isExpanded: true, .english), "Collapse")
        XCTAssertEqual(MetricCardAccessibility.expansionLabel(isExpanded: false, .portuguese), "Expandir")
        XCTAssertEqual(MetricCardAccessibility.expansionLabel(isExpanded: true, .portuguese), "Recolher")
    }

    // MARK: - Localization keys

    func testCardStringsNonEmptyInBothLanguages() {
        let texts: [LocalizedText] = [Strings.cardExpand, Strings.cardCollapse]
        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }
}
