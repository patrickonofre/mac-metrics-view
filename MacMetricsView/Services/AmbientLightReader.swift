import Foundation

/// Reads a single ambient-light sample, or `nil` when no sensor is available
/// (desktop Mac, external-only display, or a future macOS that removes the private
/// API). Absence is never an error (NFR-1/NFR-3) — the feature self-hides.
protocol AmbientLightReading {
    func readSample() -> AmbientLightSample?
}

/// Injectable seam for the Apple Silicon ALS read. The real implementation reads the
/// IOHID "Level" channel via `dlsym`; tests inject a fake so the reader's clamp /
/// absence logic runs without hardware or private API. `readLevel()` returns `nil`
/// when no ALS service responds.
protocol AmbientLightSensorSource {
    func readLevel() -> Double?
}
