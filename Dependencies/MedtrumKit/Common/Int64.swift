extension UInt64 {
    func toData(length: Int) -> Data {
        var output = Data(count: length)
        for i in 0 ..< length {
            output[i] = UInt8((self >> (i * 8)) & 0xFF)
        }

        return output
    }
}

extension Int64 {
    func toData(length: Int) -> Data {
        var output = Data(count: length)
        for i in 0 ..< length {
            output[i] = UInt8((self >> (i * 8)) & 0xFF)
        }

        return output
    }
}

extension Double {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
