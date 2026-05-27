import Foundation

/// Selects the temperature reader for the current hardware at runtime. Apple Silicon
/// reads numeric Celsius via IOKit; Intel uses the SMC reader when delivered (task-003),
/// otherwise the state-only `ProcessInfoTemperatureReader`. Numeric absence is handled
/// inside each reader (`celsius = nil`), so the fallback never regresses today's UI.
enum TemperatureReaderFactory {
    static func makeDefault() -> TemperatureReading {
        #if arch(arm64)
        return IOKitTemperatureReader()
        #else
        // Intel SMC reader is optional/deferred (task-003); fall back to state-only.
        return ProcessInfoTemperatureReader()
        #endif
    }
}
