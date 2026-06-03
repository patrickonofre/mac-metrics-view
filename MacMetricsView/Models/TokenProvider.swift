import Foundation

/// Provider whose local logs back a token figure. Only `claude`/`codex` own a
/// `TokenUsageStore`; `combined` is a selector value (see `TokenProviderSelection`),
/// never a stored-events provider (ADR-003).
///
/// `String`-raw-representable so it can key per-provider state and be persisted,
/// mirroring `TokenScope`/`TokenWindow`.
enum TokenProvider: String {
    case claude
    case codex
}

/// The user-facing provider selection driving the meter: a single provider, or the
/// `combined` view that sums both. Distinct from `TokenProvider` because `combined`
/// aggregates two stores rather than owning one (ADR-003).
///
/// `String`-raw-representable for persistence in `MetricDisplaySettings`. The default
/// selection is `combined`; a consumer decoding an unknown raw value falls back to it
/// (`TokenProviderSelection(rawValue:) ?? .combined`).
enum TokenProviderSelection: String {
    case claude
    case codex
    case combined

    /// The concrete provider(s) this selection aggregates: a single provider, or both
    /// for `combined`. The aggregation layer sums each provider's store independently.
    var providers: [TokenProvider] {
        switch self {
        case .claude: return [.claude]
        case .codex: return [.codex]
        case .combined: return [.claude, .codex]
        }
    }
}
