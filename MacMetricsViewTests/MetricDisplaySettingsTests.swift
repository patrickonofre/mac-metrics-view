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
}
