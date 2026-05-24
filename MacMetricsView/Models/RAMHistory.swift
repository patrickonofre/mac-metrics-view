import Foundation

struct RAMHistory {
    let capacity: Int
    private(set) var samples: [RAMSample]

    init(capacity: Int = 45, samples: [RAMSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: RAMSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
