import XCTest
@testable import MacMetricsView

final class TokenDailyLedgerTests: XCTestCase {

    /// 2026-06-12 00:00:00 UTC.
    private let dayStart = Date(timeIntervalSinceReferenceDate: 802_915_200)

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var calendar: Calendar { Self.utcCalendar }

    private func calendar(offsetHours: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetHours * 3_600)!
        return calendar
    }

    private func event(at date: Date, input: Int = 0, output: Int = 0) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1",
            projectDir: "p1"
        )
    }

    // MARK: - Day-key resolution

    func testDayBoundaryEventsLandOnTheirOwnKeys() {
        var ledger = TokenDailyLedger()
        // 23:59:59 of 2026-06-12 vs 00:00:00 of 2026-06-13.
        ledger.fold(event(at: dayStart.addingTimeInterval(86_399), input: 10), costUSD: 1, calendar: calendar)
        ledger.fold(event(at: dayStart.addingTimeInterval(86_400), input: 20), costUSD: 2, calendar: calendar)

        XCTAssertEqual(ledger.days["2026-06-12"]?.usage.input, 10)
        XCTAssertEqual(ledger.days["2026-06-13"]?.usage.input, 20)
    }

    func testFoldsAccumulateWithinADayAndSeparateAcrossDays() {
        var ledger = TokenDailyLedger()
        ledger.fold(event(at: dayStart.addingTimeInterval(3_600), input: 10, output: 5), costUSD: 0.5, calendar: calendar)
        ledger.fold(event(at: dayStart.addingTimeInterval(7_200), input: 30), costUSD: 1.5, calendar: calendar)
        ledger.fold(event(at: dayStart.addingTimeInterval(-3_600), input: 100), costUSD: 4, calendar: calendar)

        XCTAssertEqual(ledger.days.count, 2)
        XCTAssertEqual(ledger.days["2026-06-12"]?.usage.input, 40)
        XCTAssertEqual(ledger.days["2026-06-12"]?.usage.output, 5)
        XCTAssertEqual(ledger.days["2026-06-12"]?.costUSD ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(ledger.days["2026-06-11"]?.usage.input, 100)
    }

    // MARK: - Prune

    func testPruneKeepsExactlyTodayPlusSevenPriorDays() {
        var ledger = TokenDailyLedger()
        let now = dayStart.addingTimeInterval(12 * 3_600)   // midday 2026-06-12
        for daysBack in 0..<10 {
            ledger.fold(
                event(at: dayStart.addingTimeInterval(Double(-daysBack) * 86_400 + 3_600), input: 1),
                costUSD: 0.1,
                calendar: calendar
            )
        }
        XCTAssertEqual(ledger.days.count, 10)

        ledger.prune(now: now, calendar: calendar)

        XCTAssertEqual(ledger.days.count, 8)
        XCTAssertNotNil(ledger.days["2026-06-12"])
        XCTAssertNotNil(ledger.days["2026-06-05"])   // 7 days back — kept
        XCTAssertNil(ledger.days["2026-06-04"])      // 8 days back — dropped
        XCTAssertNil(ledger.days["2026-06-03"])
    }

    // MARK: - Weekly sum

    func testWeeklyTotalSumsNewestEightDaysAndExcludesOlder() {
        var ledger = TokenDailyLedger()
        let now = dayStart.addingTimeInterval(12 * 3_600)
        // 9 populated days: today + 8 prior; the ninth (8 days back) must not count.
        for daysBack in 0..<9 {
            ledger.fold(
                event(at: dayStart.addingTimeInterval(Double(-daysBack) * 86_400 + 3_600), input: 10),
                costUSD: 1,
                calendar: calendar
            )
        }

        let weekly = ledger.weeklyTotal(now: now, calendar: calendar)

        XCTAssertEqual(weekly.usage.input, 80)              // 8 buckets × 10
        XCTAssertEqual(weekly.costUSD, 8, accuracy: 1e-9)   // 8 buckets × $1
    }

    func testWeeklyTotalOnEmptyLedgerIsZero() {
        let weekly = TokenDailyLedger().weeklyTotal(now: dayStart, calendar: calendar)

        XCTAssertEqual(weekly.usage, .zero)
        XCTAssertEqual(weekly.costUSD, 0)
    }

    // MARK: - Codable

    func testCodableRoundTripIsLosslessForEmptyAndPopulatedStates() throws {
        let empty = TokenDailyLedger()
        let emptyDecoded = try JSONDecoder().decode(
            TokenDailyLedger.self,
            from: JSONEncoder().encode(empty)
        )
        XCTAssertEqual(empty, emptyDecoded)

        var full = TokenDailyLedger()
        for daysBack in 0..<8 {
            full.fold(
                event(at: dayStart.addingTimeInterval(Double(-daysBack) * 86_400 + 60), input: 11 + daysBack, output: 3),
                costUSD: 0.25 * Double(daysBack + 1),
                calendar: calendar
            )
        }
        let decoded = try JSONDecoder().decode(TokenDailyLedger.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(full, decoded)

        // Stability: a second encode/decode cycle yields the same value (no key drift).
        let twice = try JSONDecoder().decode(TokenDailyLedger.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(decoded, twice)
    }

    // MARK: - Timezone determinism

    func testFixedInstantLandsOnCalendarDependentDayKeys() {
        // 2026-06-12 01:00 UTC = 2026-06-11 22:00 in UTC−3, 2026-06-12 10:00 in UTC+9.
        let instant = dayStart.addingTimeInterval(3_600)
        var west = TokenDailyLedger()
        var east = TokenDailyLedger()

        west.fold(event(at: instant, input: 5), costUSD: 0.1, calendar: calendar(offsetHours: -3))
        east.fold(event(at: instant, input: 5), costUSD: 0.1, calendar: calendar(offsetHours: 9))

        XCTAssertEqual(Array(west.days.keys), ["2026-06-11"])
        XCTAssertEqual(Array(east.days.keys), ["2026-06-12"])
    }

    // MARK: - Defensive cost clamping

    func testNegativeOrNonFiniteCostFoldsAsZero() {
        var ledger = TokenDailyLedger()
        ledger.fold(event(at: dayStart, input: 1), costUSD: -5, calendar: calendar)
        ledger.fold(event(at: dayStart, input: 1), costUSD: .nan, calendar: calendar)
        ledger.fold(event(at: dayStart, input: 1), costUSD: 2, calendar: calendar)

        XCTAssertEqual(ledger.days["2026-06-12"]?.costUSD ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(ledger.days["2026-06-12"]?.usage.input, 3)
    }
}
