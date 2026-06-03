import Foundation

struct MetricDisplaySettings: Equatable {
    enum IdentifierStyle: String {
        case labels
        case icons
    }

    /// Which RAM metric the menu bar shows. App Memory is the default because it tracks
    /// app open/close, unlike the sticky "Used" value (see plan-ram-app-memory-and-pressure).
    enum RAMMenuBarMetric: String {
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

    init(
        identifierStyle: IdentifierStyle = .icons,
        ramMenuBarMetric: RAMMenuBarMetric = .appMemory,
        diskMenuBarMetric: DiskMenuBarMetric = .combined,
        tokenMenuBarWindow: TokenWindow = .today,
        tokenScope: TokenScope = .global,
        tokenProvider: TokenProviderSelection = .combined
    ) {
        self.identifierStyle = identifierStyle
        self.ramMenuBarMetric = ramMenuBarMetric
        self.diskMenuBarMetric = diskMenuBarMetric
        self.tokenMenuBarWindow = tokenMenuBarWindow
        self.tokenScope = tokenScope
        self.tokenProvider = tokenProvider
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        let ramMetric = userDefaults.string(forKey: Keys.ramMenuBarMetric)
            .flatMap(RAMMenuBarMetric.init(rawValue:)) ?? .appMemory

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

        if let rawIdentifierStyle = userDefaults.string(forKey: Keys.identifierStyle),
           let identifierStyle = IdentifierStyle(rawValue: rawIdentifierStyle) {
            return MetricDisplaySettings(
                identifierStyle: identifierStyle,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric,
                tokenMenuBarWindow: tokenWindow,
                tokenScope: tokenScope,
                tokenProvider: tokenProvider
            )
        }

        if userDefaults.object(forKey: Keys.showMetricLabels) != nil {
            return MetricDisplaySettings(
                identifierStyle: userDefaults.bool(forKey: Keys.showMetricLabels) ? .labels : .icons,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric,
                tokenMenuBarWindow: tokenWindow,
                tokenScope: tokenScope,
                tokenProvider: tokenProvider
            )
        }

        return MetricDisplaySettings(
            ramMenuBarMetric: ramMetric,
            diskMenuBarMetric: diskMetric,
            tokenMenuBarWindow: tokenWindow,
            tokenScope: tokenScope,
            tokenProvider: tokenProvider
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(identifierStyle.rawValue, forKey: Keys.identifierStyle)
        userDefaults.set(identifierStyle == .labels, forKey: Keys.showMetricLabels)
        userDefaults.set(ramMenuBarMetric.rawValue, forKey: Keys.ramMenuBarMetric)
        userDefaults.set(diskMenuBarMetric.rawValue, forKey: Keys.diskMenuBarMetric)
        userDefaults.set(tokenMenuBarWindow.rawValue, forKey: Keys.tokenMenuBarWindow)
        userDefaults.set(tokenScope.rawValue, forKey: Keys.tokenScope)
        userDefaults.set(tokenProvider.rawValue, forKey: Keys.tokenProvider)
    }
}
