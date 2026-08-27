import Foundation

struct MetricDisplaySettings: Equatable {
    enum IdentifierStyle: String {
        case labels
        case icons
    }

    enum DiskMenuBarMetric: String {
        case combined
        case split
    }

    private enum Keys {
        static let showMetricLabels = "MetricDisplaySettings.showMetricLabels"
        static let identifierStyle = "MetricDisplaySettings.identifierStyle"
        static let diskMenuBarMetric = "MetricDisplaySettings.diskMenuBarMetric"
        static let updateRate = "MetricDisplaySettings.updateRate"
    }

    var identifierStyle: IdentifierStyle
    var diskMenuBarMetric: DiskMenuBarMetric
    var updateRate: Int

    init(
        identifierStyle: IdentifierStyle = .icons,
        diskMenuBarMetric: DiskMenuBarMetric = .combined,
        updateRate: Int = 1
    ) {
        self.identifierStyle = identifierStyle
        self.diskMenuBarMetric = diskMenuBarMetric
        self.updateRate = (updateRate == 1 || updateRate == 2 || updateRate == 3) ? updateRate : 1
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        let diskMetric = userDefaults.string(forKey: Keys.diskMenuBarMetric)
            .flatMap(DiskMenuBarMetric.init(rawValue:)) ?? .combined

        let storedRate = userDefaults.integer(forKey: Keys.updateRate)
        let updateRate = (storedRate == 1 || storedRate == 2 || storedRate == 3) ? storedRate : 1

        if let rawIdentifierStyle = userDefaults.string(forKey: Keys.identifierStyle),
           let identifierStyle = IdentifierStyle(rawValue: rawIdentifierStyle) {
            return MetricDisplaySettings(
                identifierStyle: identifierStyle,
                diskMenuBarMetric: diskMetric,
                updateRate: updateRate
            )
        }

        if userDefaults.object(forKey: Keys.showMetricLabels) != nil {
            return MetricDisplaySettings(
                identifierStyle: userDefaults.bool(forKey: Keys.showMetricLabels) ? .labels : .icons,
                diskMenuBarMetric: diskMetric,
                updateRate: updateRate
            )
        }

        return MetricDisplaySettings(
            diskMenuBarMetric: diskMetric,
            updateRate: updateRate
        )
    }

    static func resolved(from userDefaults: UserDefaults = .standard) -> MetricDisplaySettings {
        load(from: userDefaults)
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(identifierStyle.rawValue, forKey: Keys.identifierStyle)
        userDefaults.set(identifierStyle == .labels, forKey: Keys.showMetricLabels)
        userDefaults.set(diskMenuBarMetric.rawValue, forKey: Keys.diskMenuBarMetric)
        userDefaults.set(updateRate, forKey: Keys.updateRate)
    }
}
