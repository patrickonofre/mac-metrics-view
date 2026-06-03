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

    init(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }
}
