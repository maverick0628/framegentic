import Foundation

public struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head: Int = 0
    private var _count: Int = 0
    public let capacity: Int

    public var count: Int { _count }

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        if _count < capacity { _count += 1 }
    }

    public func allElements() -> [Element] {
        guard _count > 0 else { return [] }
        let start = (_count < capacity) ? 0 : head
        var result: [Element] = []
        result.reserveCapacity(_count)
        for i in 0..<_count {
            let index = (start + i) % capacity
            // Every offset in 0..<_count was populated by append(); never nil.
            guard let element = storage[index] else { continue }
            result.append(element)
        }
        return result
    }

    public func slice(from startIndex: Int, to endIndex: Int) -> [Element] {
        let all = allElements()
        guard startIndex >= 0, endIndex <= all.count, startIndex < endIndex else { return [] }
        return Array(all[startIndex..<endIndex])
    }

    public mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        _count = 0
    }
}
