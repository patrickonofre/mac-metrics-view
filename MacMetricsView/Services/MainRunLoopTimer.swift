import Foundation

enum MainRunLoopTimer {
    /// A repeating timer on the main run loop in `.common` mode, so it keeps firing
    /// during run-loop tracking (e.g. while a menu is open) instead of pausing.
    /// The action runs synchronously in main-actor isolation — the timer always fires
    /// on the main thread, so `assumeIsolated` is safe and avoids an async hop.
    @MainActor
    static func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
