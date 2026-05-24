import XCTest
@testable import MacMetricsView

final class TemperatureFormattingAndHistoryTests: XCTestCase {
    func testTemperatureStateFormatsInPortuguese() {
        XCTAssertEqual(TemperatureState.normal.localizedName(in: .portuguese), "Normal")
        XCTAssertEqual(TemperatureState.warm.localizedName(in: .portuguese), "Aquecido")
        XCTAssertEqual(TemperatureState.hot.localizedName(in: .portuguese), "Quente")
        XCTAssertEqual(TemperatureState.critical.localizedName(in: .portuguese), "Crítico")
        XCTAssertEqual(TemperatureState.unavailable.localizedName(in: .portuguese), "Indisponível")
    }

    func testTemperatureStateFormatsInEnglish() {
        XCTAssertEqual(TemperatureState.normal.localizedName(in: .english), "Normal")
        XCTAssertEqual(TemperatureState.warm.localizedName(in: .english), "Warm")
        XCTAssertEqual(TemperatureState.hot.localizedName(in: .english), "Hot")
        XCTAssertEqual(TemperatureState.critical.localizedName(in: .english), "Critical")
        XCTAssertEqual(TemperatureState.unavailable.localizedName(in: .english), "Unavailable")
    }

    func testTemperatureFormatsCelsiusAsWholeDegrees() {
        XCTAssertEqual(TemperatureFormatter.celsiusString(68.4), "68 °C")
    }

    func testTemperatureFallsBackToStateWhenCelsiusIsUnavailable() {
        let normal = TemperatureSample(celsius: nil, state: .normal)
        let unavailable = TemperatureSample(celsius: nil, state: .unavailable)

        XCTAssertEqual(TemperatureFormatter.displayString(for: normal), "Normal")
        XCTAssertEqual(TemperatureFormatter.displayString(for: unavailable), "--")
    }

    func testInvalidTemperatureValuesAreRejected() {
        XCTAssertNil(TemperatureSample(celsius: .nan, state: .normal))
        XCTAssertNil(TemperatureSample(celsius: .infinity, state: .normal))
        XCTAssertNil(TemperatureSample(celsius: -1, state: .normal))
        XCTAssertNil(TemperatureSample(celsius: 151, state: .normal))
    }

    func testTemperatureSeverityMapsToMenuBarStyle() {
        XCTAssertEqual(TemperatureState.normal.menuBarTextStyle, .normal)
        XCTAssertEqual(TemperatureState.warm.menuBarTextStyle, .elevatedCPU)
        XCTAssertEqual(TemperatureState.hot.menuBarTextStyle, .highCPU)
        XCTAssertEqual(TemperatureState.critical.menuBarTextStyle, .highCPU)
        XCTAssertEqual(TemperatureState.unavailable.menuBarTextStyle, .normal)
    }

    func testTemperatureHistoryKeepsCapacityAndDropsOldSamples() throws {
        var history = TemperatureHistory(capacity: 2)

        history.append(try XCTUnwrap(TemperatureSample(timestamp: Date(timeIntervalSince1970: 1), celsius: 41, state: .normal)))
        history.append(try XCTUnwrap(TemperatureSample(timestamp: Date(timeIntervalSince1970: 2), celsius: 42, state: .normal)))
        history.append(try XCTUnwrap(TemperatureSample(timestamp: Date(timeIntervalSince1970: 3), celsius: 43, state: .normal)))

        XCTAssertEqual(history.samples.map(\.celsius), [42, 43])
    }

    func testTemperatureHistoryIgnoresSamplesWithoutCelsius() throws {
        var history = TemperatureHistory()

        history.append(try XCTUnwrap(TemperatureSample(celsius: nil, state: .normal)))

        XCTAssertTrue(history.samples.isEmpty)
    }
}
