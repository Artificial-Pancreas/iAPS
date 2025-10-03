extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else {
            return nil
        }

        let chars = hex.map { $0 }
        let bytes = stride(from: 0, to: chars.count, by: 2)
            .map { String(chars[$0]) + String(chars[$0 + 1]) }
            .compactMap { UInt8($0, radix: 16) }

        guard hex.count / bytes.count == 2 else { return nil }
        self.init(bytes)
    }

    func hexEncodedString() -> String {
        let format = "%02hhx"
        return map { String(format: format, $0) }.joined()
    }

    func toDouble() -> Double {
        Double(toInt64())
    }

    func toUInt64() -> UInt64 {
        guard count <= 8 else {
            preconditionFailure("Cannot convert Data to UInt64, size too long")
        }

        var result: UInt64 = 0
        for i in 0 ..< count {
            let shifted = UInt64(self[i]) << (8 * i)
            result |= shifted
        }

        return result
    }

    func toInt64() -> Int64 {
        guard count <= 8 else {
            preconditionFailure("Cannot convert Data to Int64, size too long")
        }

        var result: Int64 = 0
        for i in 0 ..< count {
            let shifted = Int64(self[i]) << (8 * i)
            result |= shifted
        }

        return result
    }
}
