import Foundation

struct MetricDisplaySettings: Equatable {
    enum IdentifierStyle: String {
        case labels
        case icons
    }

    /// Which RAM metric the menu bar shows. `usedTotal` ("Used / Total GB") is the default
    /// (ADR-001/002): it answers "how much of *my* Mac's RAM is in use" at a glance, where
    /// Used = Memory Used (App + Wired + Compressed). App Memory and Pressure remain as
    /// narrower alternatives.
    enum RAMMenuBarMetric: String {
        case usedTotal
        case appMemory
        case pressure
    }

    enum DiskMenuBarMetric: String {
        case combined
        case split
    }

    private enum Keys {
        static let showMetricLabels = "MetricDisplaySettings.showMetricLabels"
        static let identifierStyle = "MetricDisplaySettings.identifierStyle"
        static let ramMenuBarMetric = "MetricDisplaySettings.ramMenuBarMetric"
        static let diskMenuBarMetric = "MetricDisplaySettings.diskMenuBarMetric"
        static let tokenMenuBarWindow = "MetricDisplaySettings.tokenMenuBarWindow"
        static let tokenScope = "MetricDisplaySettings.tokenScope"
        static let tokenProvider = "MetricDisplaySettings.tokenProvider"
        static let tokenSessionBudget = "MetricDisplaySettings.tokenSessionBudget"
        static let tokenWeeklyBudget = "MetricDisplaySettings.tokenWeeklyBudget"
        static let updateRate = "MetricDisplaySettings.updateRate"
        static let usedTotalMigrationApplied = "MetricDisplaySettings.usedTotalMigrationApplied"
    }

    var identifierStyle: IdentifierStyle
    var ramMenuBarMetric: RAMMenuBarMetric
    var diskMenuBarMetric: DiskMenuBarMetric
    /// Which rolling window the menu bar token segment shows (reuses `TokenWindow`).
    var tokenMenuBarWindow: TokenWindow
    /// The persisted counting scope for the token meter (reuses `TokenScope`).
    var tokenScope: TokenScope
    /// Which provider the token meter shows: Claude, Codex, or Combined. Defaults to
    /// `combined` so Codex surfaces immediately on update (ADR-003).
    var tokenProvider: TokenProviderSelection
    /// Optional token budget for the 5h rate-limit block, in tokens; 0 = off
    /// (ADR-008 — no shipped plan limits, the number is user-owned).
    var tokenSessionBudget: Int
    /// Optional token budget for the rolling 7-day window, in tokens; 0 = off.
    var tokenWeeklyBudget: Int
    var updateRate: Int

    init(
        identifierStyle: IdentifierStyle = .icons,
        ramMenuBarMetric: RAMMenuBarMetric = .usedTotal,
        diskMenuBarMetric: DiskMenuBarMetric = .combined,
        tokenMenuBarWindow: TokenWindow = .today,
        tokenScope: TokenScope = .global,
        tokenProvider: TokenProviderSelection = .combined,
        tokenSessionBudget: Int = 0,
        tokenWeeklyBudget: Int = 0,
        updateRate: Int = 1
    ) {
        self.identifierStyle = identifierStyle
        self.ramMenuBarMetric = ramMenuBarMetric
        self.diskMenuBarMetric = diskMenuBarMetric
        self.tokenMenuBarWindow = tokenMenuBarWindow
        self.tokenScope = tokenScope
        self.tokenProvider = tokenProvider
        self.tokenSessionBudget = max(0, tokenSessionBudget)
        self.tokenWeeklyBudget = max(0, tokenWeeklyBudget)
        self.updateRate = (updateRate == 1 || updateRate == 2 || updateRate == 3) ? updateRate : 1
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        let ramMetric = userDefaults.string(forKey: Keys.ramMenuBarMetric)
            .flatMap(RAMMenuBarMetric.init(rawValue:)) ?? .usedTotal

        let diskMetric = userDefaults.string(forKey: Keys.diskMenuBarMetric)
            .flatMap(DiskMenuBarMetric.init(rawValue:)) ?? .combined

        let tokenWindow = userDefaults.string(forKey: Keys.tokenMenuBarWindow)
            .flatMap(TokenWindow.init(rawValue:)) ?? .today

        let tokenScope = userDefaults.string(forKey: Keys.tokenScope)
            .flatMap(TokenScope.init(rawValue:)) ?? .global

        // Default combined for both fresh installs and existing installs with no stored key,
        // so existing Claude-only users see Codex until they switch (ADR-003).
        let tokenProvider = userDefaults.string(forKey: Keys.tokenProvider)
            .flatMap(TokenProviderSelection.init(rawValue:)) ?? .combined

        // `integer(forKey:)` yields 0 for missing or non-numeric values; negatives
        // clamp to 0 (off) — a stored budget can never propagate as negative.
        let sessionBudget = max(0, userDefaults.integer(forKey: Keys.tokenSessionBudget))
        let weeklyBudget = max(0, userDefaults.integer(forKey: Keys.tokenWeeklyBudget))
        
        let storedRate = userDefaults.integer(forKey: Keys.updateRate)
        let updateRate = (storedRate == 1 || storedRate == 2 || storedRate == 3) ? storedRate : 1

        if let rawIdentifierStyle = userDefaults.string(forKey: Keys.identifierStyle),
           let identifierStyle = IdentifierStyle(rawValue: rawIdentifierStyle) {
            return MetricDisplaySettings(
                identifierStyle: identifierStyle,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric,
                tokenMenuBarWindow: tokenWindow,
                tokenScope: tokenScope,
                tokenProvider: tokenProvider,
                tokenSessionBudget: sessionBudget,
                tokenWeeklyBudget: weeklyBudget,
                updateRate: updateRate
            )
        }

        if userDefaults.object(forKey: Keys.showMetricLabels) != nil {
            return MetricDisplaySettings(
                identifierStyle: userDefaults.bool(forKey: Keys.showMetricLabels) ? .labels : .icons,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric,
                tokenMenuBarWindow: tokenWindow,
                tokenScope: tokenScope,
                tokenProvider: tokenProvider,
                tokenSessionBudget: sessionBudget,
                tokenWeeklyBudget: weeklyBudget,
                updateRate: updateRate
            )
        }

        return MetricDisplaySettings(
            ramMenuBarMetric: ramMetric,
            diskMenuBarMetric: diskMetric,
            tokenMenuBarWindow: tokenWindow,
            tokenScope: tokenScope,
            tokenProvider: tokenProvider,
            tokenSessionBudget: sessionBudget,
            tokenWeeklyBudget: weeklyBudget,
            updateRate: updateRate
        )
    }

    /// Resolves the display settings to use at launch, applying the one-time
    /// `usedTotal` migration exactly once (ADR-002).
    ///
    /// `display.save()` persists the *whole* struct whenever any setting changes, so an
    /// existing install that ever touched Settings has the old `appMemory` RAM default
    /// stored even if the user never picked it for RAM. A plain default flip would never
    /// reach them. This migration flips a stored `appMemory` to `usedTotal` once, then
    /// guards itself so it runs only on the first launch of the new version. A genuine
    /// `appMemory` choice is flipped too, but the RAM picker makes reverting trivial.
    /// `pressure` is left untouched (an explicit, distinct choice).
    static func resolved(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        var settings = load(from: userDefaults)

        if !userDefaults.bool(forKey: Keys.usedTotalMigrationApplied) {
            if settings.ramMenuBarMetric == .appMemory {
                settings.ramMenuBarMetric = .usedTotal
                settings.save(to: userDefaults)
            }
            userDefaults.set(true, forKey: Keys.usedTotalMigrationApplied)
        }

        return settings
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(identifierStyle.rawValue, forKey: Keys.identifierStyle)
        userDefaults.set(identifierStyle == .labels, forKey: Keys.showMetricLabels)
        userDefaults.set(ramMenuBarMetric.rawValue, forKey: Keys.ramMenuBarMetric)
        userDefaults.set(diskMenuBarMetric.rawValue, forKey: Keys.diskMenuBarMetric)
        userDefaults.set(tokenMenuBarWindow.rawValue, forKey: Keys.tokenMenuBarWindow)
        userDefaults.set(tokenScope.rawValue, forKey: Keys.tokenScope)
        userDefaults.set(tokenProvider.rawValue, forKey: Keys.tokenProvider)
        userDefaults.set(max(0, tokenSessionBudget), forKey: Keys.tokenSessionBudget)
        userDefaults.set(max(0, tokenWeeklyBudget), forKey: Keys.tokenWeeklyBudget)
        userDefaults.set(updateRate, forKey: Keys.updateRate)
    }
}

extension MetricDisplaySettings.RAMMenuBarMetric {
    /// Order the settings picker presents the modes, default (`usedTotal`) first.
    /// Defined here (not inferred from the enum) so the picker rendering stays
    /// unit-testable without constructing the SwiftUI view (ADR-002).
    static let menuBarPickerOrder: [MetricDisplaySettings.RAMMenuBarMetric] = [
        .usedTotal, .appMemory, .pressure
    ]

    /// Short label shown for this mode in the settings picker.
    func menuBarPickerLabel(_ language: AppLanguage = .current) -> String {
        switch self {
        case .usedTotal: return Strings.ramMetricUsedTotalShort(language)
        case .appMemory: return Strings.ramMetricAppMemoryShort(language)
        case .pressure: return Strings.ramMetricPressureShort(language)
        }
    }
}
