import Foundation

/// The input/output/cache token breakdown produced by aggregation, with a derived total.
///
/// A pure value type: no I/O, timers, or formatting.
struct TokenAggregate: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreation: Int
    /// Reasoning (hidden chain-of-thought) tokens. 0 for Claude, which has no such
    /// category; non-zero for Codex (ADR-002/004). Defaulted so existing four-field
    /// call sites stay source-compatible.
    let reasoning: Int

    var total: Int { input + output + cacheRead + cacheCreation + reasoning }

    /// Headline usage figure (menu bar + popover total + sparkline): input + output +
    /// reasoning. Reasoning is real billable usage so it counts toward the single number;
    /// cache (read + creation) is large and cheap, so it stays in the popover breakdown
    /// rather than dominating the figure the user reads.
    var usageTotal: Int { input + output + reasoning }

    init(input: Int, output: Int, cacheRead: Int, cacheCreation: Int, reasoning: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.reasoning = reasoning
    }

    /// Field-wise sum of two aggregates. Used to combine per-provider aggregates for the
    /// `combined` selection (ADR-003).
    static func + (lhs: TokenAggregate, rhs: TokenAggregate) -> TokenAggregate {
        TokenAggregate(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }
}
