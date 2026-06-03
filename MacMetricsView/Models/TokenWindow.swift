import Foundation

/// The rolling time window a token figure aggregates over.
///
/// `String`-raw-representable so it can be persisted by `MetricDisplaySettings`.
enum TokenWindow: String {
    case today
    case lastHour
    case last24h
    case sinceReset
}
