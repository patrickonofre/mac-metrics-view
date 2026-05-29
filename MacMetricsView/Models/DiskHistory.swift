import Foundation

struct DiskHistory {
    let capacity: Int
    private(set) var samples: [DiskSample]

    init(capacity: Int = 45, samples: [DiskSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: DiskSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
