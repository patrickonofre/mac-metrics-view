import Foundation

/// The input/output/cache token breakdown produced by aggregation, with a derived total.
///
/// A pure value type: no I/O, timers, or formatting.
struct TokenAggregate: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreation: Int

    var total: Int { input + output + cacheRead + cacheCreation }

    /// Headline usage figure (menu bar + popover total + sparkline): input + output only.
    /// Cache (read + creation) is large and cheap, so it is kept to the popover breakdown
    /// rather than dominating the single number the user reads.
    var usageTotal: Int { input + output }

    init(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }
}
