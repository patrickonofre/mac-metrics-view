import Foundation

struct TemperatureHistory {
    let capacity: Int
    private(set) var samples: [TemperatureSample]

    init(capacity: Int = 45, samples: [TemperatureSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: TemperatureSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
