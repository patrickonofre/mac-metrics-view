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

/// Bounds asynchronous sampling work for one reader. While a read is in flight, repeated
/// ticks collapse into one follow-up read. `cancel()` invalidates the in-flight completion so
/// a stopped sampler cannot restart itself after a late delivery.
@MainActor
final class CoalescingSamplingGate {
    private var isReadInFlight = false
    private var pendingWork: ((@escaping @MainActor () -> Void) -> Void)?
    private var generation = 0

    func request(_ work: @escaping (@escaping @MainActor () -> Void) -> Void) {
        guard !isReadInFlight else {
            pendingWork = work
            return
        }
        start(work)
    }

    func cancel() {
        generation &+= 1
        isReadInFlight = false
        pendingWork = nil
    }

    private func start(_ work: @escaping (@escaping @MainActor () -> Void) -> Void) {
        isReadInFlight = true
        let activeGeneration = generation
        work { [weak self] in
            self?.complete(generation: activeGeneration)
        }
    }

    private func complete(generation: Int) {
        guard generation == self.generation, isReadInFlight else { return }
        isReadInFlight = false
        guard let pendingWork else { return }
        self.pendingWork = nil
        start(pendingWork)
    }
}

/// Runs a sampler's blocking read off the main thread, then delivers the result back on the
/// main actor (PERF-01). Lets the I/O-bound readers (token logs, SMC temperature, process
/// enumeration) leave the main run loop without changing the `@MainActor` delegate contract.
///
/// The read closure captures a reader whose mutable state must therefore be touched *only*
/// from the executor — a serial queue guarantees that confinement. CPU/RAM/network readers
/// stay on the main thread: their Mach calls are sub-microsecond, so a thread hop would cost
/// more than the work.
protocol SamplingExecutor {
    func run<T>(_ read: @escaping () -> T, deliver: @escaping @MainActor (T) -> Void)
}

/// Production executor: reads on a shared serial `.utility` queue (lands on E-cores on Apple
/// Silicon) and hops back to the main queue, preserving FIFO delivery order across ticks.
final class BackgroundSamplingExecutor: SamplingExecutor {
    /// One serial queue shared by every heavy sampler, so each reader's state is confined to a
    /// single thread (no concurrent access) while still coalescing onto one background context.
    static let sharedQueue = DispatchQueue(label: "com.macmetricsview.sampling", qos: .utility)

    private let queue: DispatchQueue

    init(queue: DispatchQueue = BackgroundSamplingExecutor.sharedQueue) {
        self.queue = queue
    }

    func run<T>(_ read: @escaping () -> T, deliver: @escaping @MainActor (T) -> Void) {
        queue.async {
            let value = read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { deliver(value) }
            }
        }
    }
}

/// Test executor: runs the read and delivery inline on the caller's thread, preserving the
/// synchronous contract the existing sampler tests rely on (fire → assert in the same turn).
struct InlineSamplingExecutor: SamplingExecutor {
    func run<T>(_ read: @escaping () -> T, deliver: @escaping @MainActor (T) -> Void) {
        let value = read()
        MainActor.assumeIsolated { deliver(value) }
    }
}
