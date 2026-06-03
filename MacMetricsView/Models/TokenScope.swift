import Foundation

/// The set of Claude Code activity a token figure counts over.
///
/// `String`-raw-representable so it can be persisted by `MetricDisplaySettings`.
enum TokenScope: String {
    case global
    case project
    case session
}
