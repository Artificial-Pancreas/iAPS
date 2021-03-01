import Foundation

extension Double {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }
}
