import Foundation

/// Bounded rolling buffer of GPU samples for the popover trend sparkline.
/// Mirrors `DiskHistory` / `TemperatureHistory`: oldest samples drop once the
/// buffer exceeds `capacity`.
struct GPUHistory {
    let capacity: Int
    private(set) var samples: [GPUSample]

    init(capacity: Int = 45, samples: [GPUSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: GPUSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
