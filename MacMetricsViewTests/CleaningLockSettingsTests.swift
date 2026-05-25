import XCTest
@testable import MacMetricsView

final class CleaningLockSettingsTests: XCTestCase {

    // MARK: - Helpers

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.CleaningLock.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    // MARK: - Defaults

    func testDefaultDurationIs30Seconds() {
        XCTAssertEqual(CleaningLockSettings.defaultDuration, 30)
    }

    func testLoadReturnsDefaultWhenNothingStored() {
        let settings = CleaningLockSettings.load(from: makeUserDefaults())
        XCTAssertEqual(settings.selectedDuration, CleaningLockSettings.defaultDuration)
    }

    // MARK: - Persistence round-trip

    func testSaveAndLoadPreservesValidPreset() {
        for preset in CleaningLockSettings.presets {
            let ud = makeUserDefaults()
            let settings = CleaningLockSettings(selectedDuration: preset)
            settings.save(to: ud)
            let loaded = CleaningLockSettings.load(from: ud)
            XCTAssertEqual(loaded.selectedDuration, preset,
                           "Round-trip failed for preset \(preset)s")
        }
    }

    // MARK: - Invalid stored values fall back to default

    func testLoadFallsBackForZeroDuration() {
        let ud = makeUserDefaults()
        ud.set(0.0, forKey: "CleaningLockSettings.selectedDuration")
        let settings = CleaningLockSettings.load(from: ud)
        XCTAssertEqual(settings.selectedDuration, CleaningLockSettings.defaultDuration)
    }

    func testLoadFallsBackForNegativeDuration() {
        let ud = makeUserDefaults()
        ud.set(-5.0, forKey: "CleaningLockSettings.selectedDuration")
        let settings = CleaningLockSettings.load(from: ud)
        XCTAssertEqual(settings.selectedDuration, CleaningLockSettings.defaultDuration)
    }

    func testLoadFallsBackForArbitraryNonPresetValue() {
        let ud = makeUserDefaults()
        ud.set(999.0, forKey: "CleaningLockSettings.selectedDuration")
        let settings = CleaningLockSettings.load(from: ud)
        XCTAssertEqual(settings.selectedDuration, CleaningLockSettings.defaultDuration)
    }

    // MARK: - Presets list

    func testPresetsContainExpectedValues() {
        XCTAssertEqual(CleaningLockSettings.presets, [15, 30, 60, 120, 300])
    }

    func testDefaultDurationIsInPresets() {
        XCTAssertTrue(CleaningLockSettings.presets.contains(CleaningLockSettings.defaultDuration))
    }
}
