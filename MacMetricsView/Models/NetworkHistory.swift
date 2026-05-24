import Foundation

struct NetworkHistory {
    let capacity: Int
    private(set) var samples: [NetworkSample]

    init(capacity: Int = 45, samples: [NetworkSample] = []) {
        self.capacity = max(1, capacity)
        self.samples = Array(samples.suffix(max(1, capacity)))
    }

    mutating func append(_ sample: NetworkSample) {
        samples.append(sample)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
