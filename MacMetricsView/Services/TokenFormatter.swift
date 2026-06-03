import Foundation

/// Formats a `TokenAggregate` into menu bar and popover strings. Token volume has no
/// danger threshold in the volume-only MVP, so it always renders `.normal` (ADR-003).
enum TokenFormatter {
    /// Short, non-localized menu bar identifier, matching the `CPU` / `DISK` style.
    static let menuBarLabel = "TOK"

    /// Compact humanized count: `950`, `1.5k`, `2.3M`. One decimal for k/M keeps the
    /// width roughly stable across magnitudes.
    static func humanized(_ count: Int) -> String {
        let value = max(0, count)

        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// Menu bar segment for the selected window's aggregate. `nil` data shows a neutral
    /// placeholder rather than a misleading zero.
    static func menuBarTitle(for aggregate: TokenAggregate?, showLabel: Bool = true) -> String {
        let value = aggregate.map { humanized($0.total) } ?? "--"
        return showLabel ? "\(menuBarLabel) \(value)" : value
    }

    /// Token volume has no severity thresholds; always `.normal`.
    static func menuBarTextStyle(for aggregate: TokenAggregate?) -> CPUMenuBarTextStyle {
        .normal
    }

    /// Whether there is nothing meaningful to show (no logs or an all-zero aggregate).
    static func isEmpty(_ aggregate: TokenAggregate?) -> Bool {
        guard let aggregate else { return true }
        return aggregate.total == 0
    }

    /// The defined empty/zero state copy, never an error or bare `0`.
    static func emptyState(_ language: AppLanguage = .current) -> String {
        Strings.tokenEmptyState(language)
    }

    /// Input / output / cache breakdown rows for the popover. Cache combines read +
    /// creation into the single "cache" figure the PRD specifies.
    static func breakdown(
        for aggregate: TokenAggregate,
        language: AppLanguage = .current
    ) -> [(label: String, value: String)] {
        [
            (Strings.tokenInput(language), humanized(aggregate.input)),
            (Strings.tokenOutput(language), humanized(aggregate.output)),
            (Strings.tokenCache(language), humanized(aggregate.cacheRead + aggregate.cacheCreation))
        ]
    }
}
