import XCTest
@testable import MacMetricsView

final class MetricDisplaySettingsTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "MetricDisplaySettingsTests.suite"

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

    func testDefaultInitializerSetsDiskMenuBarMetricToCombined() {
        let settings = MetricDisplaySettings()

        XCTAssertEqual(settings.diskMenuBarMetric, .combined)
    }

    func testLoadWithoutDiskKeyDefaultsToCombined() {
        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.diskMenuBarMetric, .combined)
    }

    func testLoadWithSplitPersistedReturnsSplit() {
        userDefaults.set("split", forKey: "MetricDisplaySettings.diskMenuBarMetric")

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.diskMenuBarMetric, .split)
    }

    func testSaveWritesDiskMenuBarMetricRawValue() {
        var settings = MetricDisplaySettings()
        settings.diskMenuBarMetric = .split

        settings.save(to: userDefaults)

        XCTAssertEqual(
            userDefaults.string(forKey: "MetricDisplaySettings.diskMenuBarMetric"),
            "split"
        )

        settings.diskMenuBarMetric = .combined
        settings.save(to: userDefaults)

        XCTAssertEqual(
            userDefaults.string(forKey: "MetricDisplaySettings.diskMenuBarMetric"),
            "combined"
        )
    }

    func testLoadWithInvalidPersistedStringFallsBackToCombined() {
        userDefaults.set("garbage", forKey: "MetricDisplaySettings.diskMenuBarMetric")

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.diskMenuBarMetric, .combined)
    }

    func testUpdateRateRoundTripThroughUserDefaults() {
        var settings = MetricDisplaySettings()
        settings.updateRate = 3
        
        settings.save(to: userDefaults)
        let reloaded = MetricDisplaySettings.load(from: userDefaults)
        
        XCTAssertEqual(reloaded.updateRate, 3)
    }
    
    func testInvalidUpdateRateClampsToDefault() {
        userDefaults.set(5, forKey: "MetricDisplaySettings.updateRate")
        let reloaded = MetricDisplaySettings.load(from: userDefaults)
        XCTAssertEqual(reloaded.updateRate, 1)
        
        userDefaults.set(0, forKey: "MetricDisplaySettings.updateRate")
        let reloadedZero = MetricDisplaySettings.load(from: userDefaults)
        XCTAssertEqual(reloadedZero.updateRate, 1)
    }

    // MARK: - usedTotal one-time migration (ADR-002)

    private let migrationKey = "MetricDisplaySettings.usedTotalMigrationApplied"
    private let ramKey = "MetricDisplaySettings.ramMenuBarMetric"

    func testResolvedMigratesStoredAppMemoryToUsedTotalOnce() {
        userDefaults.set("appMemory", forKey: ramKey)

        let resolved = MetricDisplaySettings.resolved(from: userDefaults)

        XCTAssertEqual(resolved.ramMenuBarMetric, .usedTotal)
        XCTAssertEqual(userDefaults.string(forKey: ramKey), "usedTotal") // persisted
        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))           // flag set
    }

    func testResolvedDoesNotReMigrateOnceFlagIsSet() {
        // User deliberately picks appMemory after the migration already ran.
        userDefaults.set(true, forKey: migrationKey)
        userDefaults.set("appMemory", forKey: ramKey)

        let resolved = MetricDisplaySettings.resolved(from: userDefaults)

        XCTAssertEqual(resolved.ramMenuBarMetric, .appMemory)
    }

    func testResolvedPreservesExplicitPressureChoice() {
        userDefaults.set("pressure", forKey: ramKey)

        let resolved = MetricDisplaySettings.resolved(from: userDefaults)

        XCTAssertEqual(resolved.ramMenuBarMetric, .pressure)
        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))
    }

    func testResolvedFreshInstallYieldsUsedTotalAndSetsFlag() {
        let resolved = MetricDisplaySettings.resolved(from: userDefaults)

        XCTAssertEqual(resolved.ramMenuBarMetric, .usedTotal)
        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))
    }

}
