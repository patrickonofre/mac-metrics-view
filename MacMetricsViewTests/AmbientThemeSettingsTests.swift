import XCTest
@testable import MacMetricsView

final class AmbientThemeSettingsTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "AmbientThemeSettingsTests.suite"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testDefaultsAreOptInWithCalibratedBand() {
        let settings = AmbientThemeSettings()

        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.lowLux, AmbientThemeSettings.defaultLowLux)
        XCTAssertEqual(settings.highLux, AmbientThemeSettings.defaultHighLux)
        XCTAssertEqual(settings.dwellSeconds, AmbientThemeSettings.defaultDwellSeconds)
        XCTAssertGreaterThan(settings.highLux, settings.lowLux)
    }

    func testLoadWithNoKeysReturnsDefaults() {
        let settings = AmbientThemeSettings.load(from: userDefaults)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.lowLux, AmbientThemeSettings.defaultLowLux)
        XCTAssertEqual(settings.highLux, AmbientThemeSettings.defaultHighLux)
    }

    func testInvalidBandFallsBackToDefaults() {
        // highLux <= lowLux is degenerate (no dead band) → reset to default band.
        let inverted = AmbientThemeSettings(isEnabled: true, lowLux: 300, highLux: 100)

        XCTAssertEqual(inverted.lowLux, AmbientThemeSettings.defaultLowLux)
        XCTAssertEqual(inverted.highLux, AmbientThemeSettings.defaultHighLux)
        XCTAssertTrue(inverted.isEnabled)
    }

    func testNegativeDwellClampsToZero() {
        let settings = AmbientThemeSettings(dwellSeconds: -5)

        XCTAssertEqual(settings.dwellSeconds, 0)
    }

    func testSaveThenLoadRoundTrips() {
        let original = AmbientThemeSettings(isEnabled: true, lowLux: 150, highLux: 250, dwellSeconds: 30)
        original.save(to: userDefaults)

        let loaded = AmbientThemeSettings.load(from: userDefaults)

        XCTAssertEqual(loaded, original)
        XCTAssertTrue(loaded.isEnabled)
        XCTAssertEqual(loaded.lowLux, 150)
        XCTAssertEqual(loaded.highLux, 250)
        XCTAssertEqual(loaded.dwellSeconds, 30)
    }

    func testCorruptStoredBandLoadsAsDefaults() {
        userDefaults.set(true, forKey: "AmbientThemeSettings.isEnabled")
        userDefaults.set(500.0, forKey: "AmbientThemeSettings.lowLux")
        userDefaults.set(100.0, forKey: "AmbientThemeSettings.highLux")

        let loaded = AmbientThemeSettings.load(from: userDefaults)

        XCTAssertTrue(loaded.isEnabled)
        XCTAssertEqual(loaded.lowLux, AmbientThemeSettings.defaultLowLux)
        XCTAssertEqual(loaded.highLux, AmbientThemeSettings.defaultHighLux)
    }
}
