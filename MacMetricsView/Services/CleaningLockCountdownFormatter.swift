import Foundation

/// Pure, stateless formatter for the cleaning-lock countdown display.
///
/// Always clamps the `remaining` value to `[0, total]` so no impossible
/// strings (negative, exceeding duration) can reach the UI.
enum CleaningLockCountdownFormatter {

    /// Returns a human-readable countdown string.
    ///
    /// - `remaining` < 60 s  → `"Xs"`   (e.g. `"5s"`, `"59s"`)
    /// - `remaining` ≥ 60 s  → `"m:ss"` (e.g. `"1:30"`, `"2:00"`)
    ///
    /// Values outside `[0, total]` are clamped defensively.
    static func string(forRemaining remaining: TimeInterval, total: TimeInterval) -> String {
        let safeTotal  = max(0, total)
        let clamped    = min(safeTotal, max(0, remaining))
        let seconds    = Int(clamped.rounded(.up))

        if seconds >= 60 {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        } else {
            return "\(seconds)s"
        }
    }
}
