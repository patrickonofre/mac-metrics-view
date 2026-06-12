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

    // MARK: - Token budgets (Phase 3, ADR-008)

    func testFreshDefaultsLoadBothBudgetsAsZero() {
        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.tokenSessionBudget, 0)
        XCTAssertEqual(settings.tokenWeeklyBudget, 0)
    }

    func testBudgetsRoundTripThroughUserDefaults() {
        var settings = MetricDisplaySettings()
        settings.tokenSessionBudget = 2_000_000
        settings.tokenWeeklyBudget = 10_000_000

        settings.save(to: userDefaults)
        let reloaded = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(reloaded.tokenSessionBudget, 2_000_000)
        XCTAssertEqual(reloaded.tokenWeeklyBudget, 10_000_000)
    }

    func testNegativeOrNonNumericStoredBudgetLoadsAsZero() {
        userDefaults.set(-5, forKey: "MetricDisplaySettings.tokenSessionBudget")
        userDefaults.set("not-a-number", forKey: "MetricDisplaySettings.tokenWeeklyBudget")

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.tokenSessionBudget, 0)
        XCTAssertEqual(settings.tokenWeeklyBudget, 0)
    }

    func testSavingBudgetsLeavesOtherDisplaySettingsUntouched() {
        var settings = MetricDisplaySettings.load(from: userDefaults)
        settings.tokenProvider = .codex
        settings.save(to: userDefaults)

        var withBudgets = MetricDisplaySettings.load(from: userDefaults)
        withBudgets.tokenSessionBudget = 1_500_000
        withBudgets.save(to: userDefaults)

        let reloaded = MetricDisplaySettings.load(from: userDefaults)
        XCTAssertEqual(reloaded.tokenProvider, .codex)   // unrelated key intact
        XCTAssertEqual(reloaded.tokenSessionBudget, 1_500_000)
        XCTAssertEqual(reloaded.tokenWeeklyBudget, 0)
    }
}
