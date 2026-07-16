import CoreGraphics
import Foundation

extension Double {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }
}

extension Int {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

extension CGFloat {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

extension Decimal {
    func rounded(to scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}
