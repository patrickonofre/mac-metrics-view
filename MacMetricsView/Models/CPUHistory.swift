import Foundation

struct CPUHistory {
    let capacity: Int
    private(set) var samples: [CPUSample]

    init(capacity: Int = 45, samples: [CPUSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: CPUSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
