/// Search keys for many texts in four flat buffers: one allocation per buffer instead of two per text, so 100k file
/// names cost a few MB and scoring walks contiguous memory.
struct KeyStore: Sendable {
    /// Folded UTF-8 of every key, back to back.
    private(set) var bytes: [UInt8] = []
    /// The match bonus of each byte in `bytes`.
    private(set) var bonus: [UInt8] = []
    /// Key `i` is `bytes[starts[i] ..< starts[i + 1]]`.
    private(set) var starts: [UInt32] = [0]
    /// Key `i`'s byte set, as in `SearchKey.mask`.
    private(set) var masks: [UInt64] = []

    var count: Int { masks.count }

    func length(of key: Int) -> Int {
        Int(starts[key + 1] - starts[key])
    }

    mutating func append(_ text: some StringProtocol) {
        let start = bytes.count
        Folding.fold(String(text), bytes: &bytes, bonus: &bonus)
        starts.append(UInt32(bytes.count))
        masks.append(Folding.mask(of: bytes[start...]))
    }

    var memoryBytes: Int {
        bytes.capacity + bonus.capacity + starts.capacity * 4 + masks.capacity * 8
    }

    mutating func trim() {
        bytes = bytes.withUnsafeBufferPointer { Array($0) }
        bonus = bonus.withUnsafeBufferPointer { Array($0) }
        starts = starts.withUnsafeBufferPointer { Array($0) }
        masks = masks.withUnsafeBufferPointer { Array($0) }
    }

    mutating func reserveCapacity(keys: Int, bytes total: Int) {
        bytes.reserveCapacity(total)
        bonus.reserveCapacity(total)
        starts.reserveCapacity(keys + 1)
        masks.reserveCapacity(keys)
    }
}
