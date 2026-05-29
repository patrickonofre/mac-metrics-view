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
    }

    var identifierStyle: IdentifierStyle
    var ramMenuBarMetric: RAMMenuBarMetric
    var diskMenuBarMetric: DiskMenuBarMetric

    init(
        identifierStyle: IdentifierStyle = .icons,
        ramMenuBarMetric: RAMMenuBarMetric = .appMemory,
        diskMenuBarMetric: DiskMenuBarMetric = .combined
    ) {
        self.identifierStyle = identifierStyle
        self.ramMenuBarMetric = ramMenuBarMetric
        self.diskMenuBarMetric = diskMenuBarMetric
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        let ramMetric = userDefaults.string(forKey: Keys.ramMenuBarMetric)
            .flatMap(RAMMenuBarMetric.init(rawValue:)) ?? .appMemory

        let diskMetric = userDefaults.string(forKey: Keys.diskMenuBarMetric)
            .flatMap(DiskMenuBarMetric.init(rawValue:)) ?? .combined

        if let rawIdentifierStyle = userDefaults.string(forKey: Keys.identifierStyle),
           let identifierStyle = IdentifierStyle(rawValue: rawIdentifierStyle) {
            return MetricDisplaySettings(
                identifierStyle: identifierStyle,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric
            )
        }

        if userDefaults.object(forKey: Keys.showMetricLabels) != nil {
            return MetricDisplaySettings(
                identifierStyle: userDefaults.bool(forKey: Keys.showMetricLabels) ? .labels : .icons,
                ramMenuBarMetric: ramMetric,
                diskMenuBarMetric: diskMetric
            )
        }

        return MetricDisplaySettings(ramMenuBarMetric: ramMetric, diskMenuBarMetric: diskMetric)
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(identifierStyle.rawValue, forKey: Keys.identifierStyle)
        userDefaults.set(identifierStyle == .labels, forKey: Keys.showMetricLabels)
        userDefaults.set(ramMenuBarMetric.rawValue, forKey: Keys.ramMenuBarMetric)
        userDefaults.set(diskMenuBarMetric.rawValue, forKey: Keys.diskMenuBarMetric)
    }
}
