import Foundation

/// Produces the latest GPU sample, or `nil` when GPU utilization can't be read
/// (no accelerator exposing the key, or a future macOS renamed it).
protocol GPUReading {
    func readSample() -> GPUSample?
}

/// Injectable seam over the raw IOAccelerator read so `IOKitGPUReader`'s
/// clamp/validation logic is unit-testable without hardware. Returns the raw
/// `"Device Utilization %"` (nominally 0–100) or `nil` when unavailable.
protocol GPUUtilizationSource {
    func readUtilizationPercent() -> Double?
}
