import XCTest
@testable import MacMetricsView

final class TokenSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "TokenSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Defaults

    func testFreshLoadDefaultsTokenOffWindowTodayScopeGlobal() {
        let visibility = MetricVisibilitySettings.load(from: defaults)
        let display = MetricDisplaySettings.load(from: defaults)

        XCTAssertFalse(visibility.showTokens)
        XCTAssertEqual(display.tokenMenuBarWindow, .today)
        XCTAssertEqual(display.tokenScope, .global)
    }

    // MARK: - Round-trips

    func testShowTokensRoundTripsAndLeavesOtherFlagsUntouched() {
        var visibility = MetricVisibilitySettings.load(from: defaults)
        visibility.showTokens = true
        visibility.showCPU = true
        visibility.showNetwork = false
        visibility.save(to: defaults)

        let reloaded = MetricVisibilitySettings.load(from: defaults)
        XCTAssertTrue(reloaded.showTokens)
        XCTAssertTrue(reloaded.showCPU)
        XCTAssertFalse(reloaded.showNetwork)
    }

    func testTokenWindowRoundTripsEveryValue() {
        for window in [TokenWindow.today, .lastHour, .last24h, .sinceReset] {
            var display = MetricDisplaySettings.load(from: defaults)
            display.tokenMenuBarWindow = window
            display.save(to: defaults)

            XCTAssertEqual(MetricDisplaySettings.load(from: defaults).tokenMenuBarWindow, window)
        }
    }

    func testTokenScopeRoundTripsEveryValue() {
        for scope in [TokenScope.global, .project, .session] {
            var display = MetricDisplaySettings.load(from: defaults)
            display.tokenScope = scope
            display.save(to: defaults)

            XCTAssertEqual(MetricDisplaySettings.load(from: defaults).tokenScope, scope)
        }
    }

    // MARK: - Existing-install safety

    func testResolvedDoesNotEnableTokensForExistingInstall() {
        // Simulate an existing install that has stored visibility but never tokens.
        var existing = MetricVisibilitySettings(showCPU: true, showRAM: true, showNetwork: true)
        existing.save(to: defaults)

        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: false)

        XCTAssertFalse(resolved.showTokens)
        XCTAssertFalse(MetricVisibilitySettings.load(from: defaults).showTokens)
    }

    func testFreshInstallPresetKeepsTokensOff() {
        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: true)

        XCTAssertFalse(resolved.showTokens)
    }

    // MARK: - Garbage values fall back

    func testGarbageWindowAndScopeFallBackToDefault() {
        defaults.set("not-a-window", forKey: "MetricDisplaySettings.tokenMenuBarWindow")
        defaults.set("not-a-scope", forKey: "MetricDisplaySettings.tokenScope")

        let display = MetricDisplaySettings.load(from: defaults)

        XCTAssertEqual(display.tokenMenuBarWindow, .today)
        XCTAssertEqual(display.tokenScope, .global)
    }
}
