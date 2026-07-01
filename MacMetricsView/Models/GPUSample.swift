import Foundation

/// One in-memory GPU reading: instantaneous device utilization as a percentage.
///
/// Pure value type (Foundation only) so it is unit-testable without IOKit. Unlike
/// CPU/network/disk there is no two-snapshot delta — the IOAccelerator
/// `"Device Utilization %"` value is already an instantaneous 0–100 reading. Any
/// out-of-range, NaN, or negative input clamps to `0...100` via ``Double/clampedPercent``
/// so no impossible value reaches the menu bar.
struct GPUSample: Equatable {
    let timestamp: Date
    let utilizationPercent: Double

    init(timestamp: Date = Date(), utilizationPercent: Double) {
        self.timestamp = timestamp
        self.utilizationPercent = utilizationPercent.clampedPercent
    }
}
