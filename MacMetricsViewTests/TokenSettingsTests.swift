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

    // MARK: - Provider selection

    func testFreshLoadDefaultsProviderToCombined() {
        XCTAssertEqual(MetricDisplaySettings.load(from: defaults).tokenProvider, .combined)
    }

    func testExistingInstallWithoutProviderKeyDefaultsToCombined() {
        // An existing install has other token keys stored but never the provider key.
        var display = MetricDisplaySettings.load(from: defaults)
        display.tokenScope = .session
        display.tokenMenuBarWindow = .last24h
        display.save(to: defaults)
        defaults.removeObject(forKey: "MetricDisplaySettings.tokenProvider")

        let reloaded = MetricDisplaySettings.load(from: defaults)
        XCTAssertEqual(reloaded.tokenProvider, .combined)
        XCTAssertEqual(reloaded.tokenScope, .session)        // unrelated keys intact
        XCTAssertEqual(reloaded.tokenMenuBarWindow, .last24h)
    }

    func testTokenProviderRoundTripsEveryValue() {
        for provider in [TokenProviderSelection.claude, .codex, .combined] {
            var display = MetricDisplaySettings.load(from: defaults)
            display.tokenProvider = provider
            display.save(to: defaults)

            XCTAssertEqual(MetricDisplaySettings.load(from: defaults).tokenProvider, provider)
        }
    }

    func testSavingProviderLeavesOtherTokenKeysUntouched() {
        var display = MetricDisplaySettings.load(from: defaults)
        display.tokenScope = .project
        display.tokenMenuBarWindow = .lastHour
        display.tokenProvider = .codex
        display.save(to: defaults)

        let reloaded = MetricDisplaySettings.load(from: defaults)
        XCTAssertEqual(reloaded.tokenProvider, .codex)
        XCTAssertEqual(reloaded.tokenScope, .project)
        XCTAssertEqual(reloaded.tokenMenuBarWindow, .lastHour)
    }

    func testGarbageProviderFallsBackToCombined() {
        defaults.set("not-a-provider", forKey: "MetricDisplaySettings.tokenProvider")

        XCTAssertEqual(MetricDisplaySettings.load(from: defaults).tokenProvider, .combined)
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
