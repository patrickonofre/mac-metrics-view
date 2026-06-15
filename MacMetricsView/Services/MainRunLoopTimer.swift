import Foundation

enum MainRunLoopTimer {
    /// A single process-wide reference date. Every background timer aligns its fire
    /// date to this grid, so independently-scheduled samplers fire on the same
    /// wall-clock instants and the kernel can coalesce their wakeups into one.
    static let epoch = Date()

    /// A repeating timer on the main run loop in `.common` mode, so it keeps firing
    /// during run-loop tracking (e.g. while a menu is open) instead of pausing.
    /// The action runs synchronously in main-actor isolation — the timer always fires
    /// on the main thread, so `assumeIsolated` is safe and avoids an async hop.
    ///
    /// `tolerance` enables kernel timer coalescing (0 = exact, e.g. an open popover).
    /// The first fire date snaps to the next `interval` multiple from `anchor`, so all
    /// timers sharing the anchor align to one grid and fire in a single wakeup.
    @MainActor
    static func repeating(
        every interval: TimeInterval,
        tolerance: TimeInterval = 0,
        anchor: Date = MainRunLoopTimer.epoch,
        _ action: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        timer.fireDate = MainRunLoopTimer.nextFireDate(interval: interval, anchor: anchor)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// The next `interval` multiple strictly after `now`, measured from `anchor`. Exposed
    /// for tests so fire-date alignment can be asserted without a live run loop.
    static func nextFireDate(interval: TimeInterval, anchor: Date, now: Date = Date()) -> Date {
        guard interval > 0 else { return now }
        let elapsed = now.timeIntervalSince(anchor)
        let steps = floor(elapsed / interval) + 1
        return anchor.addingTimeInterval(steps * interval)
    }
}
