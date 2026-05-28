import Foundation

enum DiskSeverityThresholds {
    static let idleUpperBound: Double = 5 * 1_048_576
    static let lowUpperBound: Double = 100 * 1_048_576
    static let mediumUpperBound: Double = 800 * 1_048_576
}
