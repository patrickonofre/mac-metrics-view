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

    // MARK: - isEnabled round-trip

    func testLoadDefaultsIsEnabledToFalseWhenNothingStored() {
        XCTAssertFalse(CleaningLockSettings.load(from: makeUserDefaults()).isEnabled)
    }

    func testSaveAndLoadRoundTripsIsEnabledTrue() {
        let ud = makeUserDefaults()
        CleaningLockSettings(isEnabled: true).save(to: ud)
        XCTAssertTrue(CleaningLockSettings.load(from: ud).isEnabled)
    }

    func testSaveAndLoadRoundTripsIsEnabledFalse() {
        let ud = makeUserDefaults()
        CleaningLockSettings(isEnabled: true).save(to: ud)
        CleaningLockSettings(isEnabled: false).save(to: ud)
        XCTAssertFalse(CleaningLockSettings.load(from: ud).isEnabled)
    }

    // MARK: - resolved(from:isCurrentlyTrusted:) migration bootstrap (CLNGT-06/07)

    // CLNGT-06: no stored preference + AX already trusted → resolves enabled, preserving
    // an existing active user.
    func testResolvedWithNoStoredPreferenceAndTrustedSeedsEnabledTrue() {
        let ud = makeUserDefaults()

        let settings = CleaningLockSettings.resolved(from: ud, isCurrentlyTrusted: true)

        XCTAssertTrue(settings.isEnabled)
    }

    // CLNGT-07: no stored preference + AX not trusted → resolves disabled (no new prompt
    // for a user who never interacted with the feature).
    func testResolvedWithNoStoredPreferenceAndUntrustedSeedsEnabledFalse() {
        let ud = makeUserDefaults()

        let settings = CleaningLockSettings.resolved(from: ud, isCurrentlyTrusted: false)

        XCTAssertFalse(settings.isEnabled)
    }

    // The bootstrap persists immediately — it must run exactly once.
    func testResolvedPersistsTheBootstrapValueImmediately() {
        let ud = makeUserDefaults()

        _ = CleaningLockSettings.resolved(from: ud, isCurrentlyTrusted: true)

        XCTAssertTrue(CleaningLockSettings.load(from: ud).isEnabled)
    }

    // Edge case: an explicitly-stored false must never be re-migrated, even if the
    // current trust state would seed true.
    func testResolvedNeverReMigratesAnExplicitlyStoredFalse() {
        let ud = makeUserDefaults()
        CleaningLockSettings(isEnabled: false).save(to: ud)

        let settings = CleaningLockSettings.resolved(from: ud, isCurrentlyTrusted: true)

        XCTAssertFalse(settings.isEnabled, "an explicit false must win over the migration heuristic")
    }

    // An explicitly-stored true must also be respected as-is (not just re-derived).
    func testResolvedRespectsAnExplicitlyStoredTrueRegardlessOfCurrentTrust() {
        let ud = makeUserDefaults()
        CleaningLockSettings(isEnabled: true).save(to: ud)

        let settings = CleaningLockSettings.resolved(from: ud, isCurrentlyTrusted: false)

        XCTAssertTrue(settings.isEnabled)
    }
}
